/**
 * The module containing the main matching logic and associated symbols.
 */
module path_matcher.match;

import path_matcher.url_util;

@safe:

/// The maximum number of path segments that this library supports.
immutable size_t MAX_PATH_SEGMENTS = 64;

/**
 * The list of possible integral types that a path parameter can be annotated as.
 * Note that there may be other complex types supported in addition to these;
 * integral types are just listed here so we can generate validation with CTFE.
 */
immutable string[] PATH_PARAMETER_INTEGRAL_TYPES = [
    "byte", "ubyte",
    "short", "ushort",
    "int", "uint",
    "long", "ulong",
    "float", "double",
    "bool"
];

/**
 * Represents a path parameter that was parsed from a URL when matching it
 * against a pattern.
 */
immutable struct PathParam {
    /// The name of the path parameter.
    string name;
    /// The raw value of the path parameter.
    string value;

    /**
     * Gets the value of this path parameter, converted to the specified
     * template type. Note that this may throw a `std.conv.ConvException` if
     * you have not specified a type for validation when parsing.
     * Returns: The value, converted to the specified template type.
     */
    T getAs(T)() const {
        import std.conv : to;
        return to!(T)(this.value);
    }
}

/**
 * Contains the result of attempting to match a URL to a path pattern. This
 * includes whether there is a match at all, and if so, a set of path
 * parameters that were parsed from the URL, according to the path pattern.
 */
immutable struct PathMatchResult {
    /// Whether the URL matches the path pattern.
    bool matches;
    /// The list of all path parameters that were parsed from the URL.
    PathParam[] pathParams;

    /**
     * Converts the result to a boolean value. This is synonymous to `matches`.
     * Returns: True, if the pattern matches the pattern.
     */
    T opCast(T : bool)() const {
        return matches;
    }

    ///
    unittest {
        if (auto match = matchPath("/path", "/:name")) {
            assert(match.getPathParam("name") == "path");
        }
        else {
            assert(false);
        }

        if (auto match = matchPath("/path", "/no-match")) {
            assert(false);
        }
    }

    /**
     * Gets the path parameters as a string-to-string mapping.
     * Returns: An associative array containing the path parameters.
     */
    immutable(string[string]) pathParamsAsMap() const @trusted {
        string[string] map;
        foreach (param; this.pathParams) {
            map[param.name] = param.value;
        }
        return cast(immutable(string[string])) map;
    }

    /**
     * Gets the string value of a specified path parameter.
     * Params:
     *   name = The name of the path parameter.
     * Returns: The value of the path parameter, or null if no such parameter exists.
     */
    string getPathParam(string name) const {
        foreach (param; this.pathParams) {
            if (param.name == name) return param.value;
        }
        return null;
    }

    /**
     * Gets a specified path parameter's value converted to the specified type.
     * Params:
     *   name = The name of the path parameter to get.
     *   defaultValue = The default value to use if no such path parameter exists.
     * Returns: The value for the path parameter.
     */
    T getPathParamAs(T)(string name, T defaultValue = T.init) const {
        foreach (param; this.pathParams) {
            if (param.name == name) {
                return param.getAs!(T);
            }
        }
        return defaultValue;
    }
}

/**
 * An exception that may be thrown when parsing a path pattern string. This
 * exception will only be thrown if the programmer has made an error in defining
 * their path pattern; NOT if a user-provided URL is incorrect.
 */
class PathPatternParseException : Exception {
    this(string msg) {
        super(msg);
    }
}

/**
 * Attempts to match a given URL with a given pattern string, and parse any
 * path parameters defined by the pattern.
 * Params:
 *   url = The URL to match.
 *   pattern = The pattern to match against.
 * Returns: A result that tells whether there was a match, and contains any
 * parsed path parameters if a match exists.
 */
PathMatchResult matchPath(string url, string pattern) {
    import std.array;

    // First initialize buffers for the URL and pattern segments on the stack.
    string[MAX_PATH_SEGMENTS] urlSegmentsBuffer;
    int urlSegmentsCount = toSegments(url, urlSegmentsBuffer);
    if (urlSegmentsCount == -1) throw new PathPatternParseException("Too many URL segments.");
    scope string[] urlSegments = urlSegmentsBuffer[0 .. urlSegmentsCount];
    uint urlSegmentIdx = 0;

    string[MAX_PATH_SEGMENTS] patternSegmentsBuffer;
    int patternSegmentsCount = toSegments(pattern, patternSegmentsBuffer);
    if (patternSegmentsCount == -1) throw new PathPatternParseException("Too many pattern segments.");
    scope string[] patternSegments = patternSegmentsBuffer[0 .. patternSegmentsCount];
    uint patternSegmentIdx = 0;

    Appender!(PathParam[]) pathParamAppender = appender!(PathParam[])();

    // Now pop segments from each stack until we've consumed the whole URL and pattern.
    string urlSegment = popSegment(urlSegments, urlSegmentIdx);
    string patternSegment = popSegment(patternSegments, patternSegmentIdx);

    // Do some initial checks for special conditions:
    // If the first segment in the pattern is a multi-match wildcard, anything is a match.
    if (patternSegment !is null && patternSegment == "**") return PathMatchResult(true, []);

    bool doingMultiMatch = false;
    while (urlSegment !is null && patternSegment !is null) {
        if (patternSegment == "*") {
            // This matches any single URL segment. Skip to the next one.
            urlSegment = popSegment(urlSegments, urlSegmentIdx);
            patternSegment = popSegment(patternSegments, patternSegmentIdx);
            doingMultiMatch = false;
        } else if (patternSegment[0] == ':' && pathParamMatches(patternSegment, urlSegment)) {
            // This matches a path parameter.
            string name = extractPathParamName(patternSegment);
            string value = urlSegment;
            pathParamAppender ~= PathParam(name, value);
            urlSegment = popSegment(urlSegments, urlSegmentIdx);
            patternSegment = popSegment(patternSegments, patternSegmentIdx);
            doingMultiMatch = false;
        } else if (patternSegment == "**") {
            // This matches zero or more URL segments.
            // If this is the last pattern segment, it's a match.
            if (patternSegmentIdx == patternSegments.length) {
                return PathMatchResult(true, pathParamAppender[]);
            }
            // Otherwise, keep absorbing URL segments until we find one matching the next pattern segment.
            doingMultiMatch = true;
            patternSegment = popSegment(patternSegments, patternSegmentIdx);
        } else if (patternSegment == urlSegment) {
            // Literal segment match. Consume both and continue;
            urlSegment = popSegment(urlSegments, urlSegmentIdx);
            patternSegment = popSegment(patternSegments, patternSegmentIdx);
            doingMultiMatch = false;
        } else if (doingMultiMatch) {
            urlSegment = popSegment(urlSegments, urlSegmentIdx);
        } else {
            return PathMatchResult(false, PathParam[].init);
        }
    }
    // If not all segments were consumed, there's some extra logic to check.
    if ((patternSegment !is null && patternSegment != "**") || urlSegment !is null) {
        return PathMatchResult(false, PathParam[].init);
    }

    return PathMatchResult(true, pathParamAppender[]);
}

unittest {
    void assertMatch(string pattern, string url, bool matches, immutable string[string] pathParams = string[string].init) {
        import std.format : format;
        import std.stdio;
        PathMatchResult result = matchPath(url, pattern);
        writefln!"Asserting that matching URL %s against pattern %s results in %s and path params %s."(
            url, pattern, matches, pathParams
        );
        assert(
            result.matches == matches,
            format!"PathMatchResult.matches is not correct for\nURL:\t\t%s\nPattern:\t%s\nExpected %s instead of %s."(
                url,
                pattern,
                matches,
                result.matches
            )
        );
        if (result.matches) {
            assert(
                result.pathParamsAsMap == pathParams,
                format!(
                    "PathMatchResult.pathParams is not correct for\nURL:\t\t%s\nPattern:\t%s\n" ~
                    "Expected %s instead of %s."
                )(
                    url,
                    pattern,
                    pathParams,
                    result.pathParamsAsMap
                )
            );
        }
        writeln("\tCheck!");
    }

    assertMatch("/**", "", true);
    assertMatch("/**", "/", true);
    assertMatch("/**", "/a/b/c/d", true);
    assertMatch("/users", "/users", true);
    assertMatch("/users/*", "/users/andrew", true);
    assertMatch("/users/**", "/users", true);
    assertMatch("/users/data/**", "/users/andrew", false);
    assertMatch("/users/data/**", "/users/data", true);
    assertMatch("/users/data/**", "/users/data/andrew", true);
    assertMatch("/users/:username", "/users/andrew", true, ["username": "andrew"]);
    assertMatch("/users", "/user", false);
    assertMatch("/users", "/data", false);
    assertMatch("/users/:username/data", "/users/andrew/data", true, ["username": "andrew"]);
    assertMatch("/users/:username/data", "/users/andrew", false);
    assertMatch(
        "/users/:username/data/:dname", "/users/andrew/data/date-of-birth",
        true, ["username": "andrew", "dname": "date-of-birth"]
    );
    assertMatch("/users/all", "/users/andrew/data", false);
    assertMatch("/users/**/settings", "/users/andrew/data/a/settings", true);
    assertMatch("/users/**/settings", "/users/settings", true);
    assertMatch("/users/**/:username", "/users/andrew", true, ["username": "andrew"]);
    assertMatch("/users/:id:ulong", "/users/123", true, ["id": "123"]);
    assertMatch("/users", "/users/123", false);
}

/**
 * Checks if a path parameter pattern segment (something like ":value" or
 * ":id:int") matches a given URL segment. If a type is provided like in the
 * second example, then it'll ensure that URL segment contains a value that
 * can be converted to the specified type.
 * Params:
 *   patternSegment = The pattern segment containing the path parameter pattern.
 *   urlSegment = The URL segment containing the value for the path parameter.
 * Returns: True if the URL segment contains a valid value for the path
 * parameter, or false otherwise.
 */
private bool pathParamMatches(in string patternSegment, in string urlSegment) {
    if (
        patternSegment is null || patternSegment.length < 2 || patternSegment[0] != ':' ||
        urlSegment is null || urlSegment.length < 1
    ) {
        return false;
    }
    int typeSeparatorIdx = -1;
    for (int i = 1; i < patternSegment.length; i++) {
        if (patternSegment[i] == ':') {
            typeSeparatorIdx = i;
            break;
        }
    }
    if (typeSeparatorIdx != -1) {
        import std.conv : to, ConvException;
        import std.uuid : parseUUID, UUIDParsingException;
        import std.uni : toLower;
        if (patternSegment.length < typeSeparatorIdx + 2) return false; // The type name is too short.
        string typeName = toLower(patternSegment[typeSeparatorIdx + 1 .. $]);
        try {
            static foreach (string integralType; PATH_PARAMETER_INTEGRAL_TYPES) {
                if (typeName == integralType) {
                    mixin("to!" ~ integralType ~ "(urlSegment);");
                    return true;
                }
            }
            // Any other supported types.
            if (typeName == "uuid") {
                parseUUID(urlSegment);
                return true;
            }
            // None of the allowed types were matched.
            return false;
        } catch (ConvException e) {
            return false;
        } catch (UUIDParsingException e) {
            return false;
        }
    } else {
        return true;
    }
}

unittest {
    assert(pathParamMatches(":name", "andrew"));
    assert(pathParamMatches(":age:int", "25"));
    assert(pathParamMatches(":age:int", "0"));
    assert(!pathParamMatches(":age:int", "two"));
    assert(pathParamMatches(":value:float", "3.14"));
    assert(pathParamMatches(":flag:bool", "true"));
    assert(pathParamMatches(":flag:bool", "false"));
    assert(!pathParamMatches(":name", null));
}

/**
 * Extracts the parameter name from a path parameter pattern segment string
 * like ":name" or ":id:int".
 * Params:
 *   patternSegment = The pattern segment to parse.
 * Returns: The parameter's name, or null if the pattern segment is invalid.
 */
private string extractPathParamName(string patternSegment) {
    if (patternSegment is null || patternSegment.length < 2) {
        throw new PathPatternParseException("Cannot extract path parameter name from \"" ~ patternSegment ~ "\".");
    }
    int typeSeparatorIdx = -1;
    for (int i = 2; i < patternSegment.length; i++) {
        if (patternSegment[i] == ':') {
            typeSeparatorIdx = i;
            break;
        }
    }
    if (typeSeparatorIdx == -1) return patternSegment[1 .. $];
    return patternSegment[1 .. typeSeparatorIdx];
}

unittest {
    import std.exception : assertThrown;
    assert(extractPathParamName(":test") == "test");
    assert(extractPathParamName(":a") == "a");
    assertThrown!PathPatternParseException(extractPathParamName(":"));
    assert(extractPathParamName(":id:int") == "id");
}
