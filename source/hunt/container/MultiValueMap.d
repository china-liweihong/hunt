module hunt.container.MultiValueMap;

import hunt.container.List;
import hunt.container.Map;

alias MultiValuesMap(T) = Map!(string, List!(T));
alias MultiStringsMap = MultiValuesMap!string;


/**
 * Extension of the {@code Map} interface that stores multiple values.
 *
 * @author Arjen Poutsma
 * @since 3.0
 */
interface MultiValueMap(K, V) : Map!(K, List!(V)) {

	/**
	 * Return the first value for the given key.
	 * @param key the key
	 * @return the first value for the specified key, or {@code null} if none
	 */	
	V getFirst(K key);

	/**
	 * Add the given single value to the current list of values for the given key.
	 * @param key the key
	 * @param value the value to be added
	 */
	void add(K key, V value);

	/**
	 * Add all the values of the given list to the current list of values for the given key.
	 * @param key they key
	 * @param values the values to be added
	 * @since 5.0
	 */
	void addAll(K key, List!V values);

	/**
	 * Add all the values of the given {@code MultiValueMap} to the current values.
	 * @param values the values to be added
	 * @since 5.0
	 */
	void addAll(Map!(K, List!V) values);

	/**
	 * Set the given single value under the given key.
	 * @param key the key
	 * @param value the value to set
	 */
	void set(K key, V value);

	/**
	 * Set the given values under.
	 * @param values the values.
	 */
	void setAll(Map!(K, V) values);

	/**
	 * Returns the first values contained in this {@code MultiValueMap}.
	 * @return a single value representation of this map
	 */
	Map!(K, V) toSingleValueMap();

}
