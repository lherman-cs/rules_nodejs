"""
Repository rule for downloading a version of esbuild for the current platform
"""

_PLATFORM_SHA = {
    "darwin_64": "6c47e733742355bdec36be7311c3d3a62dbf73a5fb74a336884d3530288ee929",
    "linux_64": "1259cc662922ac3abc050262d66d74a46988f3f4be9c8104a303beacd0be844e",
    "windows_64": "1ebe99345730fb3624428135a3cb285c7c6023190bec9907fd3ece6f52ce4469",
}

_VERSION = "0.8.16"

def _esbuild_repository_impl(rctx):
    platform_sha = rctx.attr.platform_sha
    version = rctx.attr.version

    URLS = {
        "linux": {
            "sha": platform_sha["linux_64"],
            "url": "https://registry.npmjs.org/esbuild-linux-64/-/esbuild-linux-64-%s.tgz" % version,
        },
        "mac os": {
            "sha": platform_sha["darwin_64"],
            "url": "https://registry.npmjs.org/esbuild-darwin-64/-/esbuild-darwin-64-%s.tgz" % version,
        },
        "windows": {
            "sha": platform_sha["windows_64"],
            "url": "https://registry.npmjs.org/esbuild-windows-64/-/esbuild-windows-64-%s.tgz" % version,
        },
    }

    os_name = rctx.os.name.lower()
    if os_name.startswith("mac os"):
        value = URLS["mac os"]
    elif os_name.find("windows") != -1:
        value = URLS["windows"]
    elif os_name.startswith("linux"):
        value = URLS["linux"]
    else:
        fail("Unsupported operating system: " + os_name)

    rctx.download_and_extract(
        value["url"],
        sha256 = value["sha"],
        stripPrefix = "package",
    )

    if os_name.startswith("windows"):
        rctx.file("BUILD", content = """exports_files(["esbuild.exe"])""")
    else:
        rctx.file("BUILD", content = """exports_files(["bin/esbuild"])""")

esbuild_repository = repository_rule(
    implementation = _esbuild_repository_impl,
    attrs = {
        "platform_sha": attr.string_dict(
            default = _PLATFORM_SHA,
            doc = """A dict mapping the platform to the SHA256 sum for that platforms esbuild package
The following platforms and archs are supported:
* darwin_64
* linux_64
* windows_64
            """,
        ),
        "version": attr.string(
            default = _VERSION,
            doc = "The version of esbuild to use",
        ),
    },
)
