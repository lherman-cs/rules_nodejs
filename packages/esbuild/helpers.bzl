"""
Utility helper functions for the esbuild rule
"""

def strip_ext(f):
    "Strips the extension of a file."
    return f.short_path[:-len(f.extension) - 1]

def resolve_js_input(f, inputs):
    """Find a corresponding javascript entrypoint for a provided file

    Args:
        f: The file where its basename is used to match the entrypoint
        inputs: The list of files where it should take a look at

    Returns:
        Returns the file that is the corresponding entrypoint
    """
    if f.extension == "js" or f.extension == "mjs":
        return f

    no_ext = strip_ext(f)
    for i in inputs:
        if i.extension == "js" or i.extension == "mjs":
            if strip_ext(i) == no_ext:
                return i
    fail("Could not find corresponding javascript entry point for %s. Add the %s.js to your deps." % (f.path, no_ext))

def filter_files(input, endings = [".js"]):
    """Filters a list of files for specific endings

    Args:
        input: The depset or list of files
        endings: The list of endings that should be filtered for

    Returns:
        Returns the filtered list of files
    """

    # Convert input into list regardles of being a depset or list
    input_list = input.to_list() if type(input) == "depset" else input
    filtered = []

    for file in input_list:
        for ending in endings:
            if file.path.endswith(ending):
                filtered.append(file)
                continue

    return filtered
