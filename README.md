# Macwatch

Macwatch is a simple filewatching utility. You give it a list of files to watch
and a command to run when those files change and it will invoke the command.

makewatch.py is a companion script that will parse a Makefile for the
dependencies of a target and invoke make when that target's dependencies
change.
