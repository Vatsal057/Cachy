/**
 * HomeScreen — the HOME tab ("/").
 *
 * In the Flutter app the home tab shows the card library. This is a thin
 * wrapper around LibraryScreen so the tab bar and the "/library" route
 * share one implementation.
 */
import LibraryScreen from '../library/LibraryScreen';

export default function HomeScreen() {
  return <LibraryScreen />;
}
