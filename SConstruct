#!/usr/bin/env python
import os
import sys

env = SConscript("godot-cpp/SConstruct")

env.Append(CPPPATH=["source/"])

sources = (
    Glob("source/*.cpp") +
    Glob("source/geometry/*.cpp") +
    Glob("source/commands/*.cpp") +
    Glob("source/godot/*.cpp")
)

library = env.SharedLibrary(
    "project/bin/gomo{}{}".format(env["suffix"], env["SHLIBSUFFIX"]),
    source=sources,
)

Default(library)
