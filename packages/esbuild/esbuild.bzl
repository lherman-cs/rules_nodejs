"""
esbuild rule
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@build_bazel_rules_nodejs//:providers.bzl", "JSEcmaScriptModuleInfo", "JSModuleInfo", "NpmPackageInfo", "node_modules_aspect")
load("@build_bazel_rules_nodejs//internal/linker:link_node_modules.bzl", "ASPECT_RESULT_NAME", "module_mappings_aspect")
load(":helpers.bzl", "filter_files", "resolve_js_input")

def _generate_path_mapping(package_name, path):
    """Generate a path alias mapping for a jsconfig.json

    For example: {"@my-alias/*": [ "path/to/my-alias/*" ]},

    Args:
        package_name: The module name
        path: The base path of the package
    """
    pkg = {}

    # entry for the barrel files favor mjs over normal as it results
    # in smaller bundles
    pkg[package_name] = [
        path + "/index.mjs",
        path,
    ]

    # A glob import for deep package imports
    pkg[package_name + "/*"] = [path + "/*"]

    return pkg

def _write_jsconfig_file(ctx, path_alias_mappings):
    """Writes the js config file for the path alias mappings.

    Args:
        ctx: The rule context
        path_alias_mappings: Dict with the mappings

    """

    # The package path
    rule_path = paths.dirname(ctx.build_file_path)

    # Replace all segments in the path with .. join them with "/" and postfix
    # it with another / to get a relative path from the build file dir
    # to the workspace root.
    base_url_path = "/".join([".." for segment in rule_path.split("/")]) + "/"

    # declare the jsconfig_file
    jsconfig_file = ctx.actions.declare_file("%s.config.json" % ctx.attr.name)

    # write the config file
    ctx.actions.write(
        output = jsconfig_file,
        content = struct(compilerOptions = struct(
            rootDirs = ["."],
            baseUrl = base_url_path,
            paths = path_alias_mappings,
        )).to_json(),
    )

    return jsconfig_file

def _esbuild_impl(ctx):
    # For each dep, JSEcmaScriptModuleInfo is used if found, then JSModuleInfo and finally
    # the DefaultInfo files are used if the former providers are not found.
    deps_depsets = []

    # Path alias mapings are used to create a jsconfig with mappings so that esbuild
    # how to resolve custom package or module names
    path_alias_mappings = dict()

    for dep in ctx.attr.deps:
        if JSEcmaScriptModuleInfo in dep:
            deps_depsets.append(dep[JSEcmaScriptModuleInfo].sources)

        if JSModuleInfo in dep:
            deps_depsets.append(dep[JSModuleInfo].sources)
        elif hasattr(dep, "files"):
            deps_depsets.append(dep.files)

        if NpmPackageInfo in dep:
            deps_depsets.append(dep[NpmPackageInfo].sources)

        # Collect the path alias mapping to resolve packages correctly
        if hasattr(dep, ASPECT_RESULT_NAME):
            for key, value in getattr(dep, ASPECT_RESULT_NAME).items():
                path_alias_mappings.update(_generate_path_mapping(key, value[1].replace(ctx.bin_dir.path + "/", "")))

    deps_inputs = depset(transitive = deps_depsets).to_list()
    inputs = filter_files(ctx.files.entry_point, [".mjs", ".js"]) + ctx.files.srcs + deps_inputs

    metafile = ctx.actions.declare_file("%s_metadata.json" % ctx.attr.name)
    outputs = [metafile]

    entry_point = resolve_js_input(ctx.file.entry_point, inputs)

    args = ctx.actions.args()

    args.add("--bundle", entry_point.path)
    args.add("--sourcemap")
    args.add_joined(["--platform", ctx.attr.platform], join_with = "=")
    args.add_joined(["--target", ctx.attr.target], join_with = "=")
    args.add_joined(["--log-level", "info"], join_with = "=")
    args.add_joined(["--metafile", metafile.path], join_with = "=")
    args.add_joined(["--define:process.env.NODE_ENV", '"production"'], join_with = "=")

    # disable the error limit and show all errors
    args.add_joined(["--error-limit", "0"], join_with = "=")

    if ctx.attr.splitting:
        js_out = ctx.actions.declare_directory("%s" % ctx.attr.name)
        outputs.append(js_out)

        args.add("--splitting")
        args.add_joined(["--format", "esm"], join_with = "=")
        args.add_joined(["--outdir", js_out.path], join_with = "=")
    else:
        js_out = ctx.outputs.output
        js_out_map = ctx.outputs.output_map
        outputs.extend([js_out, js_out_map])

        if ctx.attr.format:
            args.add_joined(["--format", ctx.attr.format], join_with = "=")

        args.add_joined(["--outfile", js_out.path], join_with = "=")

    jsconfig_file = _write_jsconfig_file(ctx, path_alias_mappings)
    args.add_joined(["--tsconfig", jsconfig_file.path], join_with = "=")
    inputs.append(jsconfig_file)

    # Exclude modules from the bundle
    for external in ctx.attr.external:
        args.add("--external:%s" % external)

    if ctx.attr.minify:
        args.add("--minify")
    else:
        # by default, esbuild will tree-shake 'pure' functions
        # disable this unless also minifying
        args.add_joined(["--tree-shaking", "ignore-annotations"], join_with = "=")

    ctx.actions.run(
        inputs = inputs,
        outputs = outputs,
        executable = ctx.executable.esbuild,
        arguments = [args],
        progress_message = "%s Javascript %s [esbuild]" % ("Bundling" if not ctx.attr.splitting else "Splitting", entry_point.short_path),
        execution_requirements = {
            "no-remote-exec": "1",
        },
    )

    return [
        DefaultInfo(files = depset(outputs + [jsconfig_file])),
    ]

esbuild_bundle = rule(
    attrs = {
        "deps": attr.label_list(
            default = [],
            aspects = [module_mappings_aspect, node_modules_aspect],
            doc = "A list of direct dependencies that are required to build the bundle",
        ),
        "entry_point": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The bundle's entry point (e.g. your main.js or app.js or index.js)",
        ),
        "esbuild": attr.label(
            allow_single_file = True,
            default = "@esbuild//:bin/esbuild",
            executable = True,
            cfg = "exec",
            doc = "An executable for the esbuild binary, can be overridden if a custom esbuild binary is needed",
        ),
        "external": attr.string_list(
            default = [],
            doc = "A list of module names that are treated as external and not included in the resulting bundle",
        ),
        "format": attr.string(
            values = ["iife", "cjs", "esm", ""],
            mandatory = False,
            doc = """The output format of the bundle, defaults to iife when platform is browser
and cjs when platform is node. If performing code splitting, defaults to esm""",
        ),
        "minify": attr.bool(
            default = False,
            doc = """Minifies the bundle with the built in minification.
Removes whitespace, shortens identifieres and uses equivalent but shorter syntax.

Sets all --minify-* flags
            """,
        ),
        "output": attr.output(
            mandatory = False,
            doc = "Name of the output file when bundling",
        ),
        "output_map": attr.output(
            mandatory = False,
            doc = "Name of the output source map when bundling",
        ),
        "platform": attr.string(
            default = "browser",
            values = ["node", "browser", ""],
            doc = "The platform to bundle for",
        ),
        "splitting": attr.bool(
            default = False,
            doc = """If true, esbuild produces an output directory containing all the output files from code splitting 
            """,
        ),
        "srcs": attr.label_list(
            allow_files = True,
            default = [],
            doc = """Non-entry point JavaScript source files from the workspace.

You must not repeat file(s) passed to entry_point""",
        ),
        "target": attr.string(
            default = "es2015",
            doc = """Environment target (e.g. es2017, chrome58, firefox57, safari11, 
edge16, node10, default esnext)
            """,
        ),
    },
    implementation = _esbuild_impl,
)

def esbuild(name, splitting = False, **kwargs):
    """esbuild helper macro around the `esbuild_bundle` rule

    Args:
        name: The name used for this rule and output files
        splitting: If `True`, produce a code split bundle in an output directory
        **kwargs: All other args from `esbuild_bundle`
    """

    if splitting == True:
        esbuild_bundle(
            name = name,
            splitting = True,
            **kwargs
        )
    else:
        esbuild_bundle(
            name = name,
            output = "%s.js" % name,
            output_map = "%s.js.map" % name,
            **kwargs
        )
