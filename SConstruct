#!/usr/bin/env python
import os
import sys

env = SConscript("godot-cpp/SConstruct")

env.Append(CPPPATH=["source/"])

VCPKG = "C:/vcpkg/installed/x64-windows-static"
env.Append(CPPPATH=[VCPKG + "/include"])
env.Append(LIBPATH=[VCPKG + "/lib"])
env.Append(LIBS=["osdCPU"])

sources = (
    Glob("source/*.cpp") +
    Glob("source/geometry/*.cpp") +
    Glob("source/geometry/create/*.cpp") +
    Glob("source/commands/*.cpp") +
    Glob("source/godot/*.cpp")
)

library = env.SharedLibrary(
    "project/bin/gomo{}{}".format(env["suffix"], env["SHLIBSUFFIX"]),
    source=sources,
)

Default(library)
