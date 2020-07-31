# esbuild rules for Bazel

The esbuild rules runs the [esbuild](https://github.com/evanw/esbuild) bundler tool with Bazel.

## Installation

Add the `@bazel/esbuild` npm packages to your `devDependencies` in `package.json`.

```
npm install --save-dev @bazel/esbuild
```
or using yarn
```
yarn add -D @bazel/esbuild
```

Add the esbuild repository to the `WORKSPACE` file

```python
load("@npm//@bazel/esbuild:index.bzl", "esbuild_repository")

esbuild_repository(name = "esbuild")
```

The version of `esbuild` can be specified by passing the `version` and `platform_sha` attributes

```python
load("@npm//@bazel/esbuild:index.bzl", "esbuild_repository")

esbuild_repository(
    name = "esbuild",
    version = "0.7.19",
    platform_sha = {
        "darwin_64": "deadf43c0868430983234f90781e1b542975a2bc3549b2353303fac236816149",
        "linux_64": "2d25ad82dba8f565e8766b838acd3b966f9a2417499105ec10afb01611594ef1",
        "windows_64": "135b2ff549d4b1cfa4f8e2226f85ee97641b468aaced7585112ebe8c0af2d766",
    }
)
```

## Example use of esbuild

The `esbuild` rule can take a JS or TS dependency tree and bundle it to a single file, or split across multiple files, outputting a directory. 

```python
ts_library(
    name = "lib",
    srcs = ["a.ts"],
)

esbuild(
    name = "bundle",
    entry_point = "a.ts",
    deps = [":lib"],
)
```

The above will create three output files, `bundle.js`, `bundle.js.map` and `bundle_metadata.json` which contains the bundle metadata to aid in debugging and resoloution tracing.

Further options for minifying and splitting are available.
