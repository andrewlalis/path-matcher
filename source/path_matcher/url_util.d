/**
 * Auxiliary utilities for dealing with URLs, besides the main matching logic.
 */
module path_matcher.url_util;

import std.range.primitives : isRandomAccessRange, hasLength, ElementType;

@safe:

/**
 * Extracts segments from a slash-separated URL path and stores them in a given
 * `store` array which has been pre-allocated.
 * Params:
 *   path = The path to parse.
 *   store = The array to store segments in. Consider allocating this on the
 *           stack for performance improvements.
 * Returns: The number of segments that were parsed, or -1 if the given store
 * is too small to fit all of them.
 */
int toSegments(string path, string[] store) @nogc {
    uint i = 0;
    uint storeIdx = 0;
    while (i < path.length) {
        while (i < path.length && path[i] == '/') i++;
        if (i >= path.length || path[i] == '?') return storeIdx;
        immutable uint segmentStart = i;
        uint segmentEnd = i + 1;
        while (segmentEnd < path.length && path[segmentEnd] != '/' && path[segmentEnd] != '?') segmentEnd++;
        if (storeIdx == store.length) return -1;
        store[storeIdx++] = path[segmentStart .. segmentEnd];
        i = segmentEnd++;
    }
    return storeIdx;
}

unittest {
    void doTest(string path, string[] expectedSegments) {
        import std.format : format;
        string[32] segments;
        int count = toSegments(path, segments);
        assert(count >= 0);
        assert(
            segments[0..count] == expectedSegments,
            format!"Expected segments %s for path %s, but got %s."(
                expectedSegments,
                path,
                segments
            )
        );
    }

    doTest("/test", ["test"]);
    doTest("/test/", ["test"]);
    doTest("test/", ["test"]);
    doTest("/test?query=hello", ["test"]);
    doTest("/test/one", ["test", "one"]);
    doTest("/test/one", ["test", "one"]);
    doTest("/abc/123/test/yes", ["abc", "123", "test", "yes"]);
    doTest("a", ["a"]);
    doTest("a/b", ["a", "b"]);
    doTest("/a/b?c=d", ["a", "b"]);
    doTest("", []);
    doTest("/", []);
    doTest("///", []);
}

/**
 * Helper function to pop a single segment from an array of segments, and
 * increment a referenced index variable.
 * Params:
 *   segments = The list of segments to pop from.
 *   idx = The referenced index to increment.
 * Returns: The segment that was popped, or null if we've reached the end of
 * the segments list.
 */
string popSegment(I)(I segments, ref uint idx) if (
    isRandomAccessRange!I &&
    hasLength!I &&
    is(ElementType!I : string)
) {
    if (idx >= segments.length) return null;
    return segments[idx++];
}

unittest {
    string[] a = ["a", "b", "c"];
    uint idx = 0;
    assert(popSegment(a, idx) == "a");
    assert(idx == 1);
}
