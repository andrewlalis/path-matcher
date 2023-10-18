# path-matcher
Simple library for matching URLs to patterns, using a limited syntax. Inspired by Spring Web's AntMatcher syntax, with some modifications that I think make the logic simpler and more flexible.

## Usage
The library offers the following function:

```d
PathMatchResult matchPath(string url, string pattern);
```

which takes as input a user-provided `url` (usually obtained from an HTTP request or something of that nature), and a `pattern`, which is defined by the programmer.

A path pattern is a slash-separated list of *segments*, each of which can be one of the following:

1. Single-segment wildcard: `*` This pattern will match exactly one URL segment that contains any content. For example, `/app/*` will match `/app/data`, `/app/settings`, but not `/app` or `/app/data/x`.
2. Multi-segment wildcard: `**` This pattern will match zero or more URL segments that contain any content. For example, `/app/**` will match `/app`, `/app/data`, and `/app/data/settings`, but not `/other-app`. This wildcard is not *greedy*, meaning that if your path pattern contains *other* segments following a multi-segment wildcard, it'll take the quickest opportunity to match any subsequent pattern segments. For example, `/users/**/:username/data` will match `/users/andrew/data` with `username = "andrew"`, but it will also match `/users/bad-segment/andrew/data` with `username = "bad-segment"`.
3. Path parameters prefixed with `:<name>` This pattern will match any single URL segment if it has content that's acceptable for the given path parameter, and the content of that URL segment will be stored for later retrieval if the matching is successful. For example, the pattern `/users/:username` when matched with the URL `/users/andrew`, will parse and store `username = "andrew"`. You can also specify a type for the path parameter like so: `:<name>:<type>` (for example, `:user-id:int`). The following types are supported: `byte`, `ubyte`, `short`, `ushort`, `int`, `uint`, `long`, `ulong`, `float`, `double`, `bool`.
4. Literal strings. Any pattern segment that's not one of the aforementioned will be treated as a literal string when matching. For example, the pattern `/app/data` will match only the URL `/app/data`.

Here's some information about how you can deal with the `PathMatchResult` return value from attempting a match:

```d
PathMatchResult result = matchPath(
    "/app/users/123/data/export/abc",
    "/app/users/:user-id:int/data/:data-type/**"
);

// Check if a match is successful with the `matches` property.
assert(result.matches);

// You can directly access the list of path parameters.
foreach (param; result.pathParams) {
    writefln!"Path param %s = %s"(param.name, param.value);
}

// You can get the path parameters as a plain D associative array:
string[string] pathParamsMap = result.pathParamsAsMap;
foreach (name, value; pathParamsMap) {
    writefln!"Path param %s = %s"(name, value);
}

// You can also get path parameters individually:
string userIdStr = result.getPathParam("user-id");
string unknownParam = result.getPathParam("unknown");
assert(unknownParam is null); // Unknown parameters are null.

// And you can get path parameters converted to a type.
// To be safe, only do this with typed path parameters.
int userId = result.getPathParamAs!int("user-id");
```

## Example Path Patterns

Here are some examples of path patterns, and the paths that they would match with.

- `/users/*` matches with:
    - `/users/andrew`
    - `/users/john`
    - `/users/12345`

    But not with:
    - `/users`
    - `/users/john/settings`
- `/app/**` matches with:
    - `/app/data/a/b/c`
    - `/app`
    - `/app/login`

    But not with:
    - `/application`
    - `/`
- `/bank/:account-id:int/balance` matches with:
    - `/bank/12345/balance`
    - `/bank/543798/balance`

    But not with:
    - `/bank/andrew/balance`
