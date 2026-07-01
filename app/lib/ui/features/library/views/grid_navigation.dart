/// Pure grid navigation index math for keyboard arrow-key movement across the
/// library card grid. Kept free of Flutter widget imports so it can be unit- and
/// property-tested in isolation (Feature: desktop-optimization, Requirement 6.5).
library;

/// The four arrow-key directions a user can move focus in within the grid.
enum GridDirection { up, down, left, right }

/// Computes the next focused item index for an arrow-key press over a grid laid
/// out row-major with [columnCount] columns and [itemCount] items.
///
/// Direction rules:
/// - [GridDirection.left]  → `currentIndex - 1`, but only when [currentIndex] is
///   not at the start of its row (`currentIndex % columnCount != 0`); otherwise
///   the index stays put so focus never wraps to the previous row.
/// - [GridDirection.right] → `currentIndex + 1`, but only when [currentIndex] is
///   not at the end of its row AND the target is still `< itemCount`; otherwise
///   the index stays put so focus never wraps to the next row or past the end.
/// - [GridDirection.up]    → `currentIndex - columnCount` when that is `>= 0`;
///   otherwise the index stays (already on the top row).
/// - [GridDirection.down]  → `currentIndex + columnCount` when that is
///   `< itemCount`; otherwise the index stays (no full row below).
///
/// The returned index is always within `[0, itemCount)`. Degenerate inputs are
/// guarded: when [columnCount] <= 0 or [itemCount] <= 0 the function returns
/// [currentIndex] clamped into range (or `0` when there is at least one item).
int nextGridIndex({
  required int columnCount,
  required int itemCount,
  required int currentIndex,
  required GridDirection direction,
}) {
  // Guard against degenerate grids: nothing to navigate.
  if (itemCount <= 0) {
    return 0;
  }
  if (columnCount <= 0) {
    return currentIndex.clamp(0, itemCount - 1);
  }

  // Normalize the starting index into the valid range first.
  final current = currentIndex.clamp(0, itemCount - 1);

  switch (direction) {
    case GridDirection.left:
      // Stay if at the start of the row (would wrap to the previous row).
      if (current % columnCount == 0) {
        return current;
      }
      return current - 1;

    case GridDirection.right:
      final atRowEnd = current % columnCount == columnCount - 1;
      final target = current + 1;
      // Stay if at the end of the row or past the last item.
      if (atRowEnd || target >= itemCount) {
        return current;
      }
      return target;

    case GridDirection.up:
      final target = current - columnCount;
      return target >= 0 ? target : current;

    case GridDirection.down:
      final target = current + columnCount;
      return target < itemCount ? target : current;
  }
}
