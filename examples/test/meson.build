unittest_src = [
    'source/app.d',
    'source/benchmark/LinkedBlockingQueueBench.d',
    'source/common.d',
    'source/test/AtomicTest.d',
    'source/test/BigIntegerTest.d',
    'source/test/ByteBufferTest.d',
    'source/test/CompletableFutureTest2.d',
    'source/test/CompletableFutureTest.d',
    'source/test/ConverterUtilsTest.d',
    'source/test/DeductionTest.d',
    'source/test/ForkJoinPoolTest.d',
    'source/test/JsonSerializerTest.d',
    'source/test/LinkedBlockingQueueTest.d',
    'source/test/LocaleTest.d',
    'source/test/MagedQueueTest.d',
    'source/test/MimeTypeTest.d',
    'source/test/NullableTest.d',
    'source/test/NumberTest.d',
    'source/test/ObjectMappingTest.d',
    'source/test/PathMatcherTest.d',
    'source/test/PropertySetterTest.d',
    'source/test/ScheduledThreadPoolTest.d',
    'source/test/SerializationTest.d',
    'source/test/StringTokenizerTest.d',
    'source/test/TaskPoolTest.d',
    'source/test/ThreadPoolExecutorTest.d',
    'source/test/ThreadTest.d',
]

hunt_test = executable(
    'hunt-test',
    unittest_src,
    dependencies: hunt_dep,
    d_unittest: true,
    d_module_versions: d_mod_version,
    include_directories: include_directories('source'),
    link_args: link_runtime_shared_arg,
)

test('test-hunt', hunt_test)
