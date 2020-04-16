module hunt.io.channel.posix.AbstractStream;

// dfmt off
version(Posix):
// dfmt on

import hunt.collection.BufferUtils;
import hunt.collection.ByteBuffer;
import hunt.event.selector.Selector;
import hunt.Functions;
import hunt.io.channel.AbstractSocketChannel;
import hunt.io.channel.Common;
import hunt.logging.ConsoleLogger;
import hunt.system.Error;

import std.format;
import std.socket;

import core.atomic;
import core.stdc.errno;
import core.stdc.string;
import core.sys.posix.sys.socket : accept;
import core.sys.posix.unistd;
import std.experimental.allocator;
enum string ResponseData = "HTTP/1.1 200 OK\r\nContent-Length: 13\r\nConnection: Keep-Alive\r\nContent-Type: text/plain\r\nServer: Hunt/1.0\r\nDate: Wed, 17 Apr 2013 12:00:00 GMT\r\n\r\nHello, World!";

/**
TCP Peer
*/

abstract class AbstractStream : AbstractSocketChannel {
    enum BufferSize = 4096;
    private const(ubyte)[] _readBuffer;
    private ByteBuffer writeBuffer;

    /**
    * Warning: The received data is stored a inner buffer. For a data safe,
    * you would make a copy of it.
    */
    protected DataReceivedHandler dataReceivedHandler;
    protected SimpleEventHandler disconnectionHandler;
    protected SimpleActionHandler dataWriteDoneHandler;

    protected AddressFamily _family;
    protected ByteBuffer _bufferForRead;
    protected WritingBufferQueue _writeQueue;
    protected bool isWriteCancelling = false;

    private int _readBufferArrayIndex;
    private bool _asClient = true;
    private Selector _loop;

    this(Selector loop, AddressFamily family = AddressFamily.INET, size_t bufferSize = 4096 * 2 , bool asClient = true) {
        this._family = family;
        _bufferForRead = asClient ? BufferUtils.allocate(bufferSize) : loop.getReadBuffer(_readBufferArrayIndex);
        _bufferForRead.limit(cast(int)bufferSize);
        _readBuffer = cast(ubyte[])_bufferForRead.array();
        //_writeQueue = new WritingBufferQueue();
        _writeQueue = theAllocator.make!WritingBufferQueue;
        super(loop, ChannelType.TCP);
        setFlag(ChannelFlag.Read, true);
        setFlag(ChannelFlag.Write, true);
        setFlag(ChannelFlag.ETMode, true);
        _asClient = asClient;
        _loop = loop;
    }

    abstract bool isConnected() nothrow;

    override
    protected void onDisconnected()
    {
      if (!_asClient && _readBufferArrayIndex != -1)
      {
       // infof("put buff %d", _readBufferArrayIndex);
        _loop.putReadBuffer(_readBufferArrayIndex);
        _readBufferArrayIndex = -1;
      }
     // theAllocator.dispose(_writeQueue);
    }

    /**
     *
     */
    protected bool tryRead() {
        bool isDone = true;
        this.clearError();
        ptrdiff_t len = read(this.handle, cast(void*) _readBuffer.ptr, _readBuffer.length);

        // ubyte[] rb = new ubyte[BufferSize];
        // ptrdiff_t len = read(this.handle, cast(void*) rb.ptr, rb.length);
        version (HUNT_IO_DEBUG) {
            tracef("reading[fd=%d]: %d bytes", this.handle, len);
            if (len <= 32)
                infof("fd: %d, %d bytes: %(%02X %)", this.handle, len, _readBuffer[0 .. len]);
            else
                infof("fd: %d, 32/%d bytes: %(%02X %)", this.handle, len, _readBuffer[0 .. 32]);
        }

        if (len > 0) {
            if (dataReceivedHandler !is null) {
                _bufferForRead.limit(cast(int)len);
                _bufferForRead.position(0);
                dataReceivedHandler(_bufferForRead);

                // ByteBuffer bb = BufferUtils.wrap(cast(byte[])rb[0..len]);
                // dataReceivedHandler(bb);
            }

            // size_t nBytes = tryWrite(cast(ubyte[])ResponseData);

            // if(nBytes < ResponseData.length) {
            //     warning("data lost");
            // }

            // It's prossible that there are more data waitting for read in the read I/O space.
            if (len == _readBuffer.length) {
                version (HUNT_IO_DEBUG) infof("Read buffer is full read %d bytes. Need to read again.", len);
                isDone = false;
            }
        } else if (len == Socket.ERROR) {
            // https://stackoverflow.com/questions/14595269/errno-35-eagain-returned-on-recv-call
            // FIXME: Needing refactor or cleanup -@Administrator at 2018-5-8 16:06:13
            // check more error status
            this._error = errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK;
            if (_error) {
                this._errorMessage = getErrorMessage(errno);
            } else {
                debug warningf("warning on read: fd=%d, errno=%d, message=%s", this.handle,
                        errno, getErrorMessage(errno));
            }

            if(errno == ECONNRESET) {
                // https://stackoverflow.com/questions/1434451/what-does-connection-reset-by-peer-mean
                onDisconnected();
            }
        }
        else {
            version (HUNT_DEBUG)
                infof("connection broken: %s, fd:%d", _remoteAddress.toString(), this.handle);
            onDisconnected();
        }

        return isDone;
    }

    override protected void doClose() {
        version (HUNT_IO_DEBUG) {
            infof("peer socket closing: fd=%d", this.handle);
        }

        if(this.socket is null) {
            import core.sys.posix.unistd;
            core.sys.posix.unistd.close(this.handle);
        } else {
            this.socket.shutdown(SocketShutdown.BOTH);
            this.socket.close();
        }

        version (HUNT_IO_DEBUG) {
            infof("peer socket closed: fd=%d", this.handle);
        }
    }


    /**
     * Try to write a block of data.
     */
    protected ptrdiff_t tryWrite(const ubyte[] data) {
        clearError();
        // const nBytes = this.socket.send(data);
        version (HUNT_IO_DEBUG)
            tracef("try to write: %d bytes, fd=%d", data.length, this.handle);
        const nBytes = write(this.handle, data.ptr, data.length);
        // version (HUNT_IO_DEBUG)
            // tracef("actually written: %d / %d bytes, fd=%d", nBytes, data.length, this.handle);

        if (nBytes > 0) {
            return nBytes;
        }

        if (nBytes == Socket.ERROR) {
            // FIXME: Needing refactor or cleanup -@Administrator at 2018-5-8 16:07:38
            // check more error status
            // EPIPE/Broken pipe:
            // https://stackoverflow.com/questions/6824265/sigpipe-broken-pipe
            // https://github.com/angrave/SystemProgramming/wiki/Networking%2C-Part-7%3A-Nonblocking-I-O%2C-select%28%29%2C-and-epoll

            if(errno == EAGAIN) {
                version (HUNT_IO_DEBUG) {
                    warningf("warning on write: fd=%d, errno=%d, message=%s", this.handle,
                        errno, getErrorMessage(errno));
                }
            } else if(errno == EINTR || errno == EWOULDBLOCK) {
                // https://stackoverflow.com/questions/38964745/can-a-socket-become-writeable-after-an-ewouldblock-but-before-an-epoll-wait
                debug warningf("warning on write: fd=%d, errno=%d, message=%s", this.handle,
                        errno, getErrorMessage(errno));
                // eventLoop.update(this);
            } else {
                this._error = true;
                this._errorMessage = getErrorMessage(errno);
                if(errno == ECONNRESET) {
                    // https://stackoverflow.com/questions/1434451/what-does-connection-reset-by-peer-mean
                    onDisconnected();
                }
            }
        } else {
            version (HUNT_DEBUG) {
                warningf("nBytes=%d, message: %s", nBytes, lastSocketError());
                assert(false, "Undefined behavior!");
            } else {
                this._error = true;
            }
        }

        if (this._error) {
            this._errorMessage = getErrorMessage(errno);
            string msg = format("Socket error on write: fd=%d, code: %d, message=%s",
                    this.handle, errno, this.errorMessage);
            debug errorf(msg);
            errorOccurred(msg);
        }

        return 0;
    }

    private bool tryNextWrite(ByteBuffer buffer) {
        const(ubyte)[] data = cast(const(ubyte)[])buffer.getRemaining();
        version (HUNT_IO_DEBUG) {
            tracef("writting from a buffer [fd=%d], %d bytes, buffer: %s",
                this.handle, data.length, buffer.toString());
        }

        ptrdiff_t remaining = data.length;
        if(data.length == 0)
            return true;

        while(remaining > 0 && !_error && !isClosing() && !isWriteCancelling) {
            ptrdiff_t nBytes = tryWrite(data);
            version (HUNT_IO_DEBUG)
            {
                tracef("write out once: fd=%d, %d / %d bytes, remaining: %d buffer: %s",
                    this.handle, nBytes, data.length, remaining, buffer.toString());
            }

            if (nBytes > 0) {
                remaining -= nBytes;
                data = data[nBytes .. $];
            }
        }

        version (HUNT_IO_DEBUG) {
            if(remaining == 0) {
                    tracef("A buffer is written out. fd=%d", this.handle);
                return true;
            } else {
                warningf("Writing cancelled or an error ocurred. fd=%d", this.handle);
                return false;
            }
        } else {
            return remaining == 0;
        }
    }

    void resetWriteStatus() {
        _writeQueue.clear();
        atomicStore(_isWritting, false);
        isWriteCancelling = false;
    }

    /**
     * Should be thread-safe.
     */
    override void onWrite() {
        version (HUNT_IO_DEBUG)
        {
            tracef("checking status, isWritting: %s, writeBuffer: %s",
                _isWritting, writeBuffer is null ? "null" : writeBuffer.toString());
        }

        if(!_isWritting) {
            version (HUNT_IO_DEBUG)
            infof("No data needs to be written out. fd=%d", this.handle);
            return;
        }

        if(isClosing() && isWriteCancelling) {
            version (HUNT_DEBUG) infof("Write cancelled or closed, fd=%d", this.handle);
            resetWriteStatus();
            return;
        }

        // keep thread-safe here
        if(!cas(&_isBusyWritting, false, true)) {
            // version (HUNT_IO_DEBUG)
            warningf("busy writing. fd=%d", this.handle);
            return;
        }

        scope(exit) {
            _isBusyWritting = false;
        }

        if(writeBuffer !is null) {
            if(tryNextWrite(writeBuffer)) {
                writeBuffer = null;
            } else {
                version (HUNT_IO_DEBUG)
                {
                    infof("waiting to try again... fd=%d, writeBuffer: %s",
                        this.handle, writeBuffer.toString());
                }
                // eventLoop.update(this);
                return;
            }
            version (HUNT_IO_DEBUG)
                tracef("running here, fd=%d", this.handle);
        }

        if(checkAllWriteDone()) {
            return;
        }

        version (HUNT_IO_DEBUG)
        {
            tracef("start to write [fd=%d], writeBuffer %s empty", this.handle, writeBuffer is null ? "is" : "is not");
        }

        if(_writeQueue.tryDequeue(writeBuffer)) {
            if(tryNextWrite(writeBuffer)) {
                writeBuffer = null;
                checkAllWriteDone();
            } else {
            version (HUNT_IO_DEBUG)
                infof("waiting to try again: fd=%d, writeBuffer: %s", this.handle, writeBuffer.toString());

                // eventLoop.update(this);
            }
            version (HUNT_IO_DEBUG)
                warningf("running here, fd=%d", this.handle);
        }
    }
    private shared bool _isBusyWritting = false;

    protected bool checkAllWriteDone() {
        version (HUNT_IO_DEBUG) {
            import std.conv;
            tracef("checking remaining: fd=%d, writeQueue empty: %s", this.handle,
                _writeQueue.isEmpty().to!string());
        }

        if(_writeQueue.isEmpty()) {
            resetWriteStatus();
            version (HUNT_IO_DEBUG)
                infof("All data are written out: fd=%d", this.handle);
            if(dataWriteDoneHandler !is null)
                dataWriteDoneHandler(this);
            return true;
        }

        return false;
    }

    protected void doConnect(Address addr) {
        this.socket.connect(addr);
    }

    void cancelWrite() {
        isWriteCancelling = true;
    }
}
