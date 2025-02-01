# shLogger

## Introduction

shLogger is a shell script logger.  It logs a process's stdout and stderr to a log file in a readable format.  It also roughly limits long term log file growth.

## Rationale

In many environments, a program or script that is run by a managing process generates some output.  Typically this output is not retained by default.  Think of executing a shell script in X11 without popping up a window.  Also on some appliances, there is no console available to display error messages when they occur, so these messages are typically lost.  This script helps to retain useful messages that are run in background.  It also helps identify what messages came in via stdout vs stderr.

## Setup

The setup for this is quite simple:

1. Login to your system in a terminal
2. Run `shlogger --help` first for command line options
3. decide the best way to pass in the required arguments for your situation

The program allows most parameters to be set by environment variables instead of command line arguments, as described in the `--help` text.

## Issues / Technical Support

You can report issues or request support using Github issues at https://github.com/gissf1/shlogger/issues

I have implemented a plethora of tests to ensure consistent functionality.  Please look into the BATS system for more details on how to use it.

## Development & Contribution

If you would like custom changes, you can contact me for options.

If this was extremely useful to you, and you're feeling generous, please feel free to donate on my github page at https://github.com/sponsors/gissf1

Also consider contacting me with business opportunities, especially if you would like to sponsor changes to this project, or wish to offer other collaboration or contracting opportunities.

## Licensing

All files in this project are covered under the license described in the LICENSE file.  If they do not have a file header, this license applies by default as if it had the appropriate header.
