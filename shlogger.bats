#!/usr/bin/env bats

# tests for "Bats" (Bash Automated Testing System)

setup() {
    # This function runs before each test

    # get the containing directory of this bats file
    # use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0,
    # as those will point to the bats executable's location or the preprocessed file respectively
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    SCRIPT="$DIR/shlogger"
}

# compare a condition and output string if failure
function eecho() {
    echo "$@"
    false
}

@test "test that we can load the script without executing it" {
    [ -f "$SCRIPT" ]
    [ -x "$SCRIPT" ]
    source "$SCRIPT"
}

@test "fatal function exits with correct code" {
    source "$SCRIPT"

    run fatal 42 "Test error message"
    [ "$status" -eq 42 ]
    [ "${lines[0]}" = "FATAL: Test error message" ]

    run fatal 1 An error msg without quotes
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "FATAL: An error msg without quotes" ]

    # using 0 for a "fatal" code is unusual usage, but technically valid
    run fatal 0 success msg
    # echo "$status / '${lines[0]}'"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "FATAL: success msg" ]

    # INVALID: missing exit code
    run fatal missing error msg
    # echo "$status / '${lines[0]}'"
    [ "$status" -eq 2 ]
    [ "${lines[0]}" = "FATAL: error msg" ]
}

@test "prefixLines generates correctly prefixed lines on stdout" {
    source "$SCRIPT"

    # test without quoted prefix
    result=$(prefixLines prefix1 <<< "test line")
    [ "$result" = "prefix1test line" ]

    # test with quoted prefix
    result=$(prefixLines 'out: ' <<< "Test Line")
    [ "$result" = "out: Test Line" ]

    # verify return value is zero
    run prefixLines 'out: ' <<< "Test Line" > /dev/null
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "out: Test Line" ]

    # confirm that stderr is not captured
    result=$(prefixLines 'err: ' <<< "Test Line" 2>&1 1>/dev/null)
    [ "$result" = "" ]
}

@test "getTimestamp returns correct format" {
    source "$SCRIPT"
    # Expected format: YYYY-MM-DD HH:MM:SS ZONE
    result=$(getTimestamp)
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ [A-Z]{3,4}$ ]]
    # make sure it changes
    sleep 1
    result2=$(getTimestamp)
    [[ "$result2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ [A-Z]{3,4}$ ]]
    [ "$result" != "$result2" ]
}

@test "getDefaultLogfile returns sanitized filenames" {
    source "$SCRIPT"

    COMMAND="/path/to/my_script.sh"
    result=$(getDefaultLogfile)
    [ "$result" = "my_script.sh" ] || eecho "FAILED TEST: $COMMAND -> $result"

    COMMAND="/path/to/my_script.sh arg1"
    result=$(getDefaultLogfile)
    [ "$result" = "my_script.sh" ] || eecho "FAILED TEST: $COMMAND -> $result"

    TARGET_RESULT="my_script.sh"
    for PREFIX in \
        '/path/to/my_script.sh' \
        '/path/00/to/my_script.sh' \
        '/path/to/../my_script.sh' \
        ; do
        for SUFFIX in '' ' arg1' ' arg1 arg2' ; do
            COMMAND="${PREFIX}${SUFFIX}"
            result=$(getDefaultLogfile)
            [ "$result" = "$TARGET_RESULT" ] || eecho "FAILED TEST: $COMMAND -> $result"
        done
    done

    # test that all valid characters are not mangled
    TARGET_RESULT="+,-.0123456789:@ABCDEFGHIJKLMNOPQRSTUVWXYZ^_abcdefghijklmnopqrstuvwxyz"
    COMMAND="/path/to/$TARGET_RESULT"
    result=$(getDefaultLogfile)
    [ "$result" = "$TARGET_RESULT" ] || eecho "FAILED TEST: $COMMAND -> $result"

    # test that each invalid character is mangled
    INVALID_CHARS='!"#$%&'"'"'()*=[]{}\|;<>?~`'
    COUNT=${#INVALID_CHARS}
    for INDEX in $( seq 0 $(( COUNT - 1 )) ) ; do
        CH=${INVALID_CHARS:$INDEX:1}
        #prepare the command
        COMMAND="/path/to/BEGIN.$CH.END"
        result=$(getDefaultLogfile)
        [ "$result" = "BEGIN._.END" ] || eecho "FAILED TEST #$INDEX: $COMMAND -> $result"
    done

    # '/' is a path separator, so is treated very differently
    COMMAND="/path/to/BEGIN./.END"
    result=$(getDefaultLogfile)
    [ "$result" = ".END" ] || eecho "FAILED TEST: $COMMAND -> $result"

    # test control (< 0x20) and extended (>= 127) characters
    # skipping 0, 9, 0xa, 0x20, 0x7f
    for ORD in `seq 1 8` `seq 0xb 0x1f` `seq 127 255` ; do
        COMMAND=$( printf "/path/to/BEGIN.$( printf "\\\\x%02x" $ORD ).END" )
        result=$(getDefaultLogfile)
        [ "$result" = "BEGIN._.END" ] || eecho "FAILED ORD TEST #$ORD: $COMMAND -> $result"
    done
}

@test "setting MAXLOGSIZE updates the --help output" {
    source "$SCRIPT"

    # test various good values for MAXLOGSIZE
    for VALUE in 9876543210 104857600 10485760 1048576 1024 513 512 ; do
        MAXLOGSIZE=$VALUE
        FAILMSG="MAXLOGSIZE=$MAXLOGSIZE"
        run main -h
        [ "$status" -eq 1 ] || eecho "$FAILMSG"
        [ "$MAXLOGSIZE" == "$VALUE" ] || eecho -e "$FAILMSG\n -> $MAXLOGSIZE"
        
        LN=8
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'"
        grep -q '^  -s, --size=SIZE ' <<< "${lines[$LN]}" || eecho -e "$FAILMSG"
        [[ "${lines[$LN]}" =~ ,\ default:\ ([0-9]+)\)$ ]] || eecho -e "$FAILMSG"
        
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'\nBASH_REMATCH[1]='${BASH_REMATCH[1]}'"
        [ "${BASH_REMATCH[1]}" = "$MAXLOGSIZE" ] || eecho -e "$FAILMSG"
    done

    # test various bad values for MAXLOGSIZE (less than 512 should error)
    for VALUE in 511 510 500 256 128 8 4 2 1 0 -1 -511 -512 -513 a abc; do
        MAXLOGSIZE=$VALUE
        FAILMSG="MAXLOGSIZE=$MAXLOGSIZE"
        run main -h
        [ "$status" -eq 1 ] || eecho "$FAILMSG"
        [ "$MAXLOGSIZE" == "$VALUE" ] || eecho -e "$FAILMSG\n -> $MAXLOGSIZE"

        # find error message
        LN=1
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'"
        [ "${lines[$LN]}" = "Invalid MAXLOGSIZE value: $MAXLOGSIZE" ] || eecho -e "$FAILMSG"

        # find default line in help output
        LN=9
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'"
        grep -q '^  -s, --size=SIZE ' <<< "${lines[$LN]}" || eecho -e "$FAILMSG"
        [[ "${lines[$LN]}" =~ ,\ default:\ ([0-9]+)\)$ ]] || eecho -e "$FAILMSG"

        FAILMSG="$FAILMSG\nBASH_REMATCH[1]='${BASH_REMATCH[1]}'"
        [ "${BASH_REMATCH[1]}" != "$MAXLOGSIZE" ] || eecho -e "$FAILMSG"
    done

    # cleanup
    unset MAXLOGSIZE
}

@test "setting LOGFILE updates the --help output" {
    source "$SCRIPT"

    # test various good values for LOGFILE
    for VALUE in \
        /path/to/log \
        /path/to/log.log \
        ./test.log \
        ./path/to/test.log \
        ./path/to/../../test.log
    do
        LOGFILE=$VALUE
        FAILMSG="LOGFILE=$LOGFILE"
        run main -h
        [ "$status" -eq 1 ] || eecho "$FAILMSG"
        [ "$LOGFILE" == "$VALUE" ] || eecho -e "$FAILMSG\n -> $LOGFILE"

        # find error message
        LN=1
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'"
        [[ "${lines[$LN]}" =~ ^usage: ]] || eecho -e "$FAILMSG"

        # find default line in help output
        LN=7
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'"
        grep -q '^  -o, --output=FILE ' <<< "${lines[$LN]}" || eecho -e "$FAILMSG"
        [[ "${lines[$LN]}" =~ default:\ (.*)\)$ ]] || eecho -e "$FAILMSG"

        FAILMSG="$FAILMSG\nBASH_REMATCH[1]='${BASH_REMATCH[1]}'"
        [ "${BASH_REMATCH[1]}" = "$LOGFILE" ] || eecho -e "$FAILMSG"
    done

    # cleanup
    unset LOGFILE
}

@test "calling with -o updates the --help output" {
    source "$SCRIPT"

    # test various good values for LOGFILE
    for VALUE in \
        /path/to/log \
        /path/to/log.log \
        ./test.log \
        ./path/to/test.log \
        ./path/to/../../test.log
    do
        FAILMSG="VALUE=$VALUE"
        run main -o "$VALUE" -h
        [ "$status" -eq 1 ] || eecho "$FAILMSG"

        # find error message
        LN=1
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'"
        [[ "${lines[$LN]}" =~ ^usage: ]] || eecho -e "$FAILMSG"

        # find default line in help output
        LN=7
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'"
        grep -q '^  -o, --output=FILE ' <<< "${lines[$LN]}" || eecho -e "$FAILMSG"
        [[ "${lines[$LN]}" =~ default:\ (.*)\)$ ]] || eecho -e "$FAILMSG"

        FAILMSG="$FAILMSG\nBASH_REMATCH[1]='${BASH_REMATCH[1]}'"
        [ "${BASH_REMATCH[1]}" = "$VALUE" ] || eecho -e "$FAILMSG"
    done
}

@test "calling with -s updates the --help output" {
    source "$SCRIPT"

    # test various good values for MAXLOGSIZE
    for VALUE in 9876543210 104857600 10485760 1048576 1024 513 512 ; do
        FAILMSG="VALUE=$VALUE"
        run main -s $VALUE -h
        [ "$status" -eq 1 ] || eecho "$FAILMSG"
        
        LN=8
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'"
        grep -q '^  -s, --size=SIZE ' <<< "${lines[$LN]}" || eecho -e "$FAILMSG"
        [[ "${lines[$LN]}" =~ ,\ default:\ ([0-9]+)\)$ ]] || eecho -e "$FAILMSG"
        
        FAILMSG="$FAILMSG\nBASH_REMATCH[1]='${BASH_REMATCH[1]}'"
        [ "${BASH_REMATCH[1]}" = "$VALUE" ] || eecho -e "$FAILMSG"
    done

    # test various bad values for MAXLOGSIZE (less than 512 should error)
    for VALUE in 511 510 500 256 128 8 4 2 1 0 -1 -511 -512 -513 a abc; do
        FAILMSG="VALUE=$VALUE"
        run main -s $VALUE -h
        [ "$status" -eq 1 ] || eecho "$FAILMSG"

        # find error message
        LN=1
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'"
        [ "${lines[$LN]}" = "Invalid MAXLOGSIZE value: $VALUE" ] || eecho -e "$FAILMSG"

        # find default line in help output
        LN=9
        FAILMSG="$FAILMSG\nlines[$LN]='${lines[$LN]}'"
        grep -q '^  -s, --size=SIZE ' <<< "${lines[$LN]}" || eecho -e "$FAILMSG"
        [[ "${lines[$LN]}" =~ ,\ default:\ ([0-9]+)\)$ ]] || eecho -e "$FAILMSG"

        FAILMSG="$FAILMSG\nBASH_REMATCH[1]='${BASH_REMATCH[1]}'"
        [ "${BASH_REMATCH[1]}" != "$VALUE" ] || eecho -e "$FAILMSG"
    done
}

verifyTestOutput() {
    # $1  LOGFILE
    # $2  search string (uses default if missing)
    local LOGFILE="$1"
    local SEARCH="$2"
    SEARCH=${SEARCH:-: test line}
    [ "$status" -eq 0 ] || eecho "Expected status 0, got $status"
    [ -f "$LOGFILE" ] || eecho "Expected log file to exist, but it didn't"
    grep -q "$SEARCH" "$LOGFILE" || eecho "Expected log file to contain '$SEARCH', but it didn't"
}

verifyTestOutputAndCleanup() {
    # $1  LOGFILE
    local LOGFILE="$1"
    run verifyTestOutput "$@"

    # generate output on failure
    [ $status == 0 ] || eecho -e "$output"

    # cleanup
    [ ! -f "$LOGFILE" ] || rm "$LOGFILE"

    return $status
}

@test "calling generates a log file" {
    source "$SCRIPT"

    local MAXLOGSIZE=512
    local LOGFILE="$BATS_TEST_TMPDIR/test.log"
    local LINE="test line"
    run main -s $MAXLOGSIZE -o "$LOGFILE" echo "$LINE"
    #status=$?
    [ $status != 0 ] && ls -l "$BATS_TEST_TMPDIR"

    verifyTestOutputAndCleanup "$LOGFILE"
}

@test "calling with -- generates a log file" {
    source "$SCRIPT"

    local MAXLOGSIZE=512
    local LOGFILE="$BATS_TEST_TMPDIR/test.log"
    local LINE="test line"
    run main -s $MAXLOGSIZE -o "$LOGFILE" -- echo "$LINE"

    verifyTestOutputAndCleanup "$LOGFILE"
}

@test "calling with long arguments generates a log file" {
    source "$SCRIPT"

    local MAXLOGSIZE=512
    local LOGFILE="$BATS_TEST_TMPDIR/test.log"
    local LINE="test line"
    run main --size $MAXLOGSIZE --output "$LOGFILE" -- echo "$LINE"

    verifyTestOutputAndCleanup "$LOGFILE"
}

@test "calling with long-equals arguments generates a log file" {
    source "$SCRIPT"

    local MAXLOGSIZE=512
    local LOGFILE="$BATS_TEST_TMPDIR/test.log"
    local LINE="test line"
    run main --size=$MAXLOGSIZE --output="$LOGFILE" -- echo "$LINE"

    verifyTestOutputAndCleanup "$LOGFILE"
}

@test "calling with environment variables generates a log file" {
    source "$SCRIPT"

    export MAXLOGSIZE=512
    export LOGFILE="$BATS_TEST_TMPDIR/test.log"
    local LINE="test line"
    run main echo "$LINE"

    verifyTestOutputAndCleanup "$LOGFILE"
}

@test "calling and capturing stderr in generated log file" {
    source "$SCRIPT"

    export MAXLOGSIZE=512
    export LOGFILE="$BATS_TEST_TMPDIR/test.log"
    run main awk 'BEGIN { print "test line" >> "/dev/stderr" ; exit(0); }'

    local LOGINFO=$( ls -l "$LOGFILE" )
    local LOGCAT=$( cat "$LOGFILE" )
    verifyTestOutputAndCleanup "$LOGFILE" "err: test line" || eecho -e "LOGFILE info=$LOGINFO\n========================================\n$LOGCAT\n========================================"
}

@test "test appending to log" {
    source "$SCRIPT"

    export MAXLOGSIZE=512
    export LOGFILE="$BATS_TEST_TMPDIR/test.log"
    local LINES=4
    ! [ $(( ( $LINES * 11 ) + ( $LINES * 4 * 77 ) )) -lt $MAXLOGSIZE ] || eecho "ERROR: the number of bytes used by $LINES LINES (x2) would not exceed MAXLOGSIZE ($MAXLOGSIZE).  Fix this test."

    local INDEX
    for INDEX in `seq 1 $LINES`; do
        local LINE="test line $INDEX!"
        run main echo "$LINE"
        verifyTestOutput "$LOGFILE" "$LINE" || eecho "LINE=$LINE"
    done
    verifyTestOutput "$LOGFILE" "test line 1!" || eecho -e "ERROR: line 1 is missing after $LINES appends;\nFileInfo=$( ls -l "$LOGFILE" )\n========================================\n$( cat "$LOGFILE" )\n========================================"

    # append more lines
    for INDEX in `seq $(( LINES + 1 )) $(( LINES * 2 ))`; do
        # test with longer lines to ensure we are > 512 bytes
        local LINE=$( printf "test line $INDEX - 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" )
        run main printf "%s\n%s\n%s\n%s\n" "$LINE" "$LINE" "$LINE" "$LINE"
        verifyTestOutput "$LOGFILE" "$LINE" || eecho "LINE=$LINE"

    done
    # make sure line 1 has been flushed out
    ! verifyTestOutput "$LOGFILE" "test line 1!" || eecho "ERROR: line 1 should be missing at this point"

    verifyTestOutputAndCleanup "$LOGFILE"
}

@test "calling with log error condition: missing path" {
    bats_require_minimum_version 1.5.0
    source "$SCRIPT"

    export MAXLOGSIZE=512
    export LOGFILE="$BATS_TEST_TMPDIR/missing/test.log"
    local LINE="test line"
    run -1 main echo "$LINE"

    [ "$status" -eq 1 ] || eecho "Expected status 1, got $status"
    [ ! -f "$LOGFILE" ] || eecho "Expected log file to be missing, but it exists: $( ls -l "$LOGFILE" )"

    LN=0
    FAILMSG="output:\n$output"
    [ "${lines[$LN]}" == "FATAL: Unable to create path to LOGFILE: $LOGFILE" ] || eecho -e "$FAILMSG"
}

@test "calling with log error condition: no perms on dir" {
    bats_require_minimum_version 1.5.0
    source "$SCRIPT"

    local LOGDIR="$BATS_TEST_TMPDIR/noperms"
    mkdir "$LOGDIR"
    chmod 000 "$LOGDIR"

    export MAXLOGSIZE=512
    export LOGFILE="$LOGDIR/test.log"
    local LINE="test line"
    run main echo "$LINE"

    [ "$status" -eq 1 ] || eecho "Expected status 1, got $status"
    chmod 550 "$LOGDIR"
    [ ! -f "$LOGFILE" ] || eecho "Expected log file to be missing, but it exists: $( ls -l "$LOGFILE" )"

    LN=0
    FAILMSG="output:\n$output"
    [ "${lines[$LN]}" == "FATAL: Unable to create LOGFILE: $LOGFILE" ] || eecho -e "$FAILMSG"

    # cleanup
    [ ! -d "$LOGDIR" ] || rmdir "$LOGDIR"
}

@test "calling with log error condition: no perms on file" {
    bats_require_minimum_version 1.5.0
    source "$SCRIPT"

    export LOGFILE="$BATS_TEST_TMPDIR/test.log"
    touch "$LOGFILE"
    chmod 000 "$LOGFILE"

    export MAXLOGSIZE=512
    local LINE="test line"
    run main echo "$LINE"

    [ "$status" -eq 1 ] || eecho "Expected status 1, got $status"
    [ -f "$LOGFILE" ] || eecho "Expected log file to exist, but it didn't"
    [ ! -s "$LOGFILE" ] || eecho "Expected log file to be empty, but it isn't: $( ls -l "$LOGFILE" )"

    LN=0
    FAILMSG="output:\n$output"
    [ "${lines[$LN]}" == "FATAL: Unable to write to LOGFILE: $LOGFILE" ] || eecho -e "$FAILMSG"

    # cleanup
    [ ! -f "$LOGFILE" ] || rm -f "$LOGFILE"
}

@test "ensure that we have addressed all TODO lines in script" {
    ! grep -n 'TODO' "$SCRIPT" | grep -Ev 'or possible TODO$'
}

@test "ensure that we have addressed all TODO lines in bats test" {
    bats_require_minimum_version 1.5.0
    ! grep -n 'TODO' "$BATS_TEST_FILENAME" | grep -Ev '! grep -n '"'"'TODO'"'" | grep -Ev '@test ".*TODO'
}
