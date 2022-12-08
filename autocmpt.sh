# For ksh93

## ---------------------------------------------------------------------
##
##
##
##
##                         KSH93 AUTOCOMP.
##
##
##
##   Put the folder "ksh93_autocmpt" into ~/.local/share/
##   then source this script in ~/.kshrc.
##
##   Command completion doesn't work yet but it can complete file names
##   and stuff like git {clone,push,pull} etc.
##
##   Security Warning: this file contains sorcery that may not be safe
##   if your yet-to-be-completed input contains $() or ``. It's still
##   probably much safer than zsh's default behaviour but looser than
##   bash's.
##
##   If your input buffer contains weird commands that 1) does not use
##   anything in $PATH, 2) when evaluated in a restricted sub-shell
##   manage to find a way to change the state of the parent shell or the
##   OS's state, then a <TAB> key will cause the side effect. Furthermore
##   if this weird command is also non-idempotent then the behaviour is
##   undefined.
##
##
##
## ---------------------------------------------------------------------
##
##
## Copyright (c) 2022 Hao Chi Kiang
##
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to deal
## in the Software without restriction, including without limitation the rights
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
## copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all
## copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
## SOFTWARE.
##
## ---------------------------------------------------------------------
ORIG_PS1="`typeset -f PS1`"
function PS1.get {
    if (( g_state == 1 )); then
        print '\E[2K\c'
        cclear 1
    fi
    eval "$ORIG_PS1"
}

typeset -a g_result
typeset -a g_splitted
typeset -i g_state=0
typeset -i g_nline=0

function jaileval {
    ## Should brace expansion, pathname expansion etc. shouldn't be done after
    ## $(pwd) for example, otherwise you're asking for bugs... But here how should
    ## I deal with it? Later on I won't have a chance to check if './*' came from
    ## a $(print "./*") or is it real...
    (
        PATH=''
        exec 2>/dev/null
        set -o noglob
        set +o braceexpand
        set -r
        ## Try evaluate first and return the actual exit code via \0Y or \0N.
        ##
        ## This is because it's very difficult to get the return code from
        ## outside this once this is piped to read -r -A -d, as ksh has the
        ## behaviour of terminating this subshell mid-way when read decided to
        ## finish (?).
        ##
        ## Adding a space like ( $1 ) will break thing.
        if eval "y=($1); IFS=$'\a'; z=\"\${y[*]}\"; print - \"$z\c\"" 1>&2; then
            eval "y=($1); IFS=$'\a'; z=\"\${y[*]}\"; print - \"$z\c\""
            printf '\0Y'
        else
            printf '\0N'
        fi
    )
}

typeset -a closequotes
closequotes[0]='\c';closequotes[1]=\';closequotes[2]='\"'
function jailevalguess {
    typeset ocmd t
    typeset -a R
    typeset -i retval j k=0
    for ((j=0; j<${#closequotes[*]}; ++j)); do
#        print '---' >&2
#        print "EVAL: >>${ printf "%s${closequotes[j]}" "${1}";}<<" >&2
#        print '---' >&2
        ocmd="$( printf "%s${closequotes[j]}" "${1}";)"
#        print "OCMD: >""$ocmd""<"
        jaileval "${ocmd}" | { IFS=$'\a' read -r -A -d $'\0' R; read -r -d $'\0' t;}
        if [[ "$t" = 'Y' ]]; then
            retval=$j
            break
        else
            retval=128
        fi
    done
    if (( retval != 128 )); then
#        print ">>>>${R[1]}<<<<" >&2
        IFS=$'\a'
        print - "${R[*]}\c"
        printf '\0Y'
    else
        printf '\0N'
    fi
    return $retval
}


## Split a line into words but strip away any non-builtin command executions. Can
## guard against rm -rf / but not bullet-proof against crafted malicious code. It
## should be safe assuming the user doesn't copy-paste insane stuff into his terminal
## and press TAB...
##
## Example:
##    wordsplit 'y z `pwd` `ls`/foo ${PWD}/bar'
##    printf '%s\n' g_splitted[0] g_splitted[1] g_splitted[2] g_splitted[3]
function wordsplit {  #If the last argument starts with a ' for example then it's just eliminated.
    typeset w
    typeset -i j=0
    set -A g_splitted
    jailevalguess "$1" | IFS=$'\a' read -r -d $'\0' -A g_splitted
#    print "0:${words[0]}"; print "1:${words[1]}"; print "2:${words[2]}"; print "3:${words[3]
}

## Tokenize the original user's input into sementic arguments (not "words" as defined
## in ksh93 manual).
##
## It's slow and brute-force, but perhaps the only way to go unless we write our
## own tokenizer or extract ksh93's C code... KSH93's built-in autocomplete doesn't
## understand parameter expansion etc. because they probably tokenize lexically
## into "words". Here I'm being a bit ambitious that the autocompletor should
## understand parameter/command/brace expansions etc, hence the complexity.
typeset -a g_lextoks
typeset -i g_ntok
typeset -a g_tags
typeset -i g_lextokgood g_curonspace

function tokenize_orig {
    typeset x="$1" arg1="$1"
    typeset -i oi=0 lenorig="${#x}" ti=0 pt=0
    typeset rslt
    typeset ch
    x="${x} "
    set -A g_lextoks
    set -A g_tags
    g_ntok=0
    g_lextokgood=0
    g_curonspace=0
    while :; do
        ch="${x:oi:1}"
        test "$ch" = \\
        while :; do
            while [[ -n "${ch#[[:space:]]}" ]]; do
                ch="${x:$((++oi)):1}"
            done
            if [[ "$ch" = \\ ]]; then
                ch="${x:$((++oi)):1}"
                continue
            else
                break
            fi
        done
#        print "OI: $oi       LENORIG=${lenorig}"
        if ((oi > lenorig)); then
            break
        else
            # \0 etc.
#            print "PT: $pt   OI:$oi  CH:>>$ch<<"
#            print "JAILEVAL ARGS: >>${x:$pt:$((oi-pt))}<<"
            jailevalguess "${x:$pt:$((oi-pt))}" | IFS=$'\a' read -r -d $'\0' -A rslt
#            print "JAILEVAL RSLT: >>${rslt}<<"
#            print "GSPLITED[TI]: ${g_splitted[$ti]}"
            if [[ "${rslt[0]}" = "${g_splitted[$ti]}" ]]; then
                g_tags[$((ti++))]=$((oi-1))
                pt=$((oi+1))
            fi
            : $((oi++))
        fi
    done
    ## Have we gotten enough parameters?
#    print "NG_TAGS ${#g_tags[*]} NGSPLITTED ${#g_splitted[*]}"
    if [[ ${#g_tags[*]} = ${#g_splitted[*]} ]]; then
        pt=0;
        for ((i=0; i<${#g_tags[*]}; ++i)); do
            g_lextoks[$i]="${arg1:pt:((g_tags[i]-pt+1))}"
            pt=$((g_tags[i]+2))
        done
        if [[ ${g_tags[$((i-1))]} -lt $((.sh.edcol - 1)) ]]; then
            g_lextoks[$i]=''
            g_splitted[$i]=''
            g_curonspace=1
        else
            g_curonspace=0
        fi
        g_lextokgood=0
    else
        g_lextokgood=1
    fi
    g_ntok=${#g_lextoks[*]}
}

typeset esc_smcup="${ tput smcup;}"
typeset esc_rmcup="${ tput rmcup;}"
typeset esc_lines="${ tput lines;}"
typeset esc_sc="${ tput sc;}"
typeset esc_rc="${ tput rc;}"
typeset esc_civis="${ tput civis;}" 
typeset esc_cnorm="${ tput cnorm;}"   ## This one doesn't work?

# TODO EXECUTE USERS PS1.get.
function cshow {
    # TODO: CHECK IF THIS IS TALLER THAN THE ENTIRE SCREEN! If yes then do some paging(?)
    # yash uses a custom tput pager; bash just launches more and do no completion at all.
    # zsh just print the entire thing to the terminal and returns to the prompt.
    typeset -i i="$(print -r - "${1}"|wc -l)"
    if [[ "$i" -gt "$(($(tput lines)-2))" ]]; then
        print -rn - "${esc_smcup}"
        cclear
        ## This asking isn't that straightforward... You can't override a keytrap here.
        ## So you'll need a new state.
        ## print 'Display all '"${#_autocmp_g_result[*]} possibilities? (y/n) \c"
        print -rn - "${1}"|less       # More doesn't catch the Enter key for some reasons...?
        print -rn - "${esc_rmcup}"
        return
    fi
    g_nline=$i
    while [[ $i -gt 0 ]]; do
        print '\ED\c'
        i=$((i-1))
    done
    print "\E[${g_nline}A\c"
    print -rn - "${esc_sc}"
    print "\n${1}\c"
    print -rn - "${esc_rc}"
    g_state=1
}
function cclear {
    typeset -i nostartshift=${1}
    typeset -i i=${g_nline}
    print -rn - "${esc_sc}"
    if (( nostartshift == 1 )); then
        i=$((i-1))
        print -n $'\e[2K'
    fi
    while [[ $i -gt 0 ]]; do
        print -n $'\n\e[2K'
        i=$((i-1))
    done
    print -rn - "${esc_rc}"
    g_nline=0
    g_state=0
#    print "cclear called"
}
function absroot {
    cd "$(dirname "$1")"
    printf "%s/%s\n" "$(pwd)" "$(basename "$1")"
    cd "$OLDPWD"
}
typeset g_completor=''
function getcandidate {
    typeset -i j=0
    typeset -i found=0
    typeset root completor_root file
    if [[ -z "$AUTOCMPT_ROOT" ]]; then
        root="$HOME/.local/share/ksh93_autocmpt"
    else
        root="$AUTOCMPT_ROOT"
    fi
    root="$(absroot "${root}")"
    mkdir -p "${root}"
    completor_root="${root}/completors"

    # Check if the cursor is at the command itself. If yes, set the completor to the
    # command completor.
    if (( ${#g_splitted[*]} == 1 )); then
        found=1
        #TODO: Make this work. But this should be sourced in a subshell.
        file="${completor_root}/___CMD"
    fi

    # Check if there's a file called _CMD, if so just execute it and
    # get return into an array line-by-line
    if (( found == 0 )); then
        [[ ! -d "${completor_root}" ]] && print "WARNING: cannot find autocomplete directory";
        for file in "${completor_root}"/*; do
            if [[ "$(basename "$file")" = _"${g_splitted[0]}" && -x "$file" ]]; then
                found=1;
                break
            fi
        done
    fi
    # g_splitted doesn't match any completors. Try using the raw token?
    if (( found == 0 && g_lextokgood == 0 )); then
        for file in "${completor_root}"/*; do
            if [[ "$(basename "$file")" = _"${g_lextoks[0]}" && -x "$file" ]]; then
                found=1;
                break
            fi
        done
    fi
    # Use fallback if found nothing.
    if (( found == 0 )); then
        #TODO: I think this should be sourced in a subshell instead... or not?
        file="${completor_root}/___FALLBACK"
    fi
    set -A g_result
    g_completor="$file"
    "$g_completor" "${g_splitted[@]}" | IFS=$'\a' read -r -d $'\0' -A g_result

    # If a specialized completor doesn't say anything then fallback file names
    if (( found != 0 && (${#g_result[*]} == 0 ||
                             (${#g_result[*]} == 1 && ${#g_result[0]} == 0)) )); then
        g_completor="${completor_root}/___FALLBACK"
        "$g_completor" "${g_splitted[@]}" | IFS=$'\a' read -r -d $'\0' -A g_result
    fi
}
typeset g_view
function fmtresult {
    ## TODO: Should be more flexible, in particular, there are cases where / shouldn't be
    ## trimmed from viewing...
    if [[ "$(basename "$g_completor")" = '___FALLBACK' ]]; then
        typeset -a V
        typeset q
        typeset -i j
        for ((j=0; j<${#g_result[*]}; ++j)); do
# We can use base name instead but it's very, very slow for big folders.
            V[$j]="${ basename "${g_result[$j]}";}"
#            if [[ "${g_result[$j]}" = */ ]]; then
#                q="${g_result[$j]:0:$((${#g_result[$j]} - 1))}"
#                V[$j]="${q%%+(*\/)}/"
#            else
#                V[$j]="${g_result[$j]%%+(*\/)}"
#            fi
            [[ -d "${g_result[$j]}" ]] && V[$j]="${V[$j]}/"
        done
        g_view="$(COLUMNS=$(tput cols) column <(printf "%s\n" "${V[@]}"))"
    else
        g_view="$(COLUMNS=$(tput cols) column <(printf "%s\n" "${g_result[@]}"))"
    fi
}

typeset g_quoted
function quoteresult {  ## Guess if user has hanging ', $', or " and adapt to it.
    if [[ -z "$1" ]]; then
        g_quoted=''
    elif [[ -z "$2" ]]; then
        barequoteresult "$1"
## The below patterns causes a miserably slow loop that needs to be killed with -9.
#    elif [[ "$2" = *(*)*(%(\'\'E\\)|%(\"\"Q\'E\\))\'*([^\']) ]]; then
    elif [[ "$2" = *([^\"\'])*(%(\'\'E\\)|%(\"\"Q\'E\\))\$\'*([^\']) ]]; then
        open_dollarsinglequoteresult "$1" "$3"
    elif [[ "$2" = *([^\"\'])*(%(\'\'E\\)|%(\"\"Q\'E\\))\'*([^\']) ]]; then
        open_singlequoteresult "$1" "$3"
    elif [[ "$2" = *([^\"\'])*(%(\'\'E\\)|%(\"\"Q\'E\\))\"*([^\"]) ]]; then
        open_doublequoteresult "$1" "$3"
    else
        barequoteresult "$1"
    fi
}

function barequoteresult {
    typeset input0="$1"
    typeset input1="${input0//\'/\\\'}"
    typeset input2="${input1//\"/\\\"}"
    typeset input3="${input2// /\\ }"
    typeset input4="${input3//$/\\$}"
    typeset input5="${input4//\`/\\\`}"
    typeset input6="${input5//\(/\\\(}"
    typeset input7="${input6//\)/\\\)}"
    typeset input8="${input7//>/\\>}"
    typeset input9="${input8//</\\<}"
    typeset input10="${input9//|/\\|}"
    typeset input11="${input10//\{/\\\{}"
    typeset input12="${input11//\}/\\\}}"
    typeset input13="${input12//#/\\#}"
    typeset input14="${input13//~/\\~}"
    typeset input15="${input14//	/\\t}"
    typeset input16="${input15//\*/\\*}"
    typeset input17="${input16//\[/\\\[}"
    typeset input18="${input17//\]/\\\]}"
    typeset input19="${input18//\?/\\\?}"
    typeset input20="${input19//\!/\\\!}"
    typeset input21="${input20//\&/\\\&}"
    g_quoted="$input21"
}
function open_singlequoteresult {
    typeset input0="$1"
    typeset input1="${input0//\'/\\\'}"
    # ASCII tabs won't work in .sh.edtext so we replace it.
    typeset input2="${input1//	/\'\$\'\\t\'\'}"
    g_quoted="${input2}"
    (( $2 == 0 )) && g_quoted="${g_quoted}'"
}
function open_dollarsinglequoteresult {
    typeset input0="$1"
    typeset input1="${input0//\'/\\\'}"
    typeset input2="${input1//\\/\\\\}"
    typeset input3="${input1//	/\\t}"
    g_quoted="${input3}"
    (( $2 == 0 )) && g_quoted="${g_quoted}'"
}
function open_doublequoteresult {
    typeset input0="$1"
    typeset input1="${input0//\"/\\\"}"
    typeset input2="${input1//\\/\\\\}"
    typeset input3="${input2//\`/\\\`}"
    typeset input4="${input3//\$/\\\$}"
    typeset input5="${input4//	/\"\$\'\\t\'\"}"
    # Escaping like "\!" doesn't work like normal. It's insane.
    typeset input6="${input5//\!/\"\\\!\"}"
    g_quoted="${input6}"
    (( $2 == 0 )) && g_quoted="${g_quoted}\""
}


## Extract a prefixing part of matches that is common
typeset g_common
function commonpart {
    g_common=''
    typeset c="${g_result[0]:0:1}"
    typeset -i j k=0 finish=0 minl=0
    typeset -i ncand=${#g_result[*]}
    minl="${#g_result[0]}"
    for ((j=0; j<ncand; ++j)); do
        [[ $minl -gt ${#g_result[$j]} ]] && minl=${#g_result[$j]}
    done
    while ((finish == 0 && k < minl)); do
        for ((j=1; j<ncand; ++j)); do
            if [[ ! "${g_result[j]:k:1}" = "$c"*(*) ]];then
               finish=1
               break;
            fi
        done
        ## If it's gone this far, and not yet done, c is in the common
        if (( finish == 0 )); then
            g_common="${g_common}${c}"
            : $((++k))
            c="${g_result[0]:k:1}"
        else
            : $((++k))
        fi
    done
}
oldkeytrap="$(trap -p KEYBD)"
function keytrap {
    typeset -i completed=0
    if [[ g_state -eq 1 ]]; then
        print -rn - "${esc_civis}"
#        cclear
    fi
    if [[ "${.sh.edchar}" = $'\n' || "${.sh.edchar}" = $'\r' ]]; then
        print -rn - "${esc_civis}"
        cclear
    fi
    if [[ "${.sh.edchar}" = $'\t' ]]; then
        ## Glob will be expended into multiple elements of the array, when splitting
        ## which is not fine.
        wordsplit "${.sh.edtext:0:${.sh.edcol}}"
        tokenize_orig "${.sh.edtext:0:${.sh.edcol}}"
        if (( ${#g_splitted[*]} == 0 || g_lextokgood == 1 )); then
            .sh.edchar=''
            return
        fi
#       TODO: glob doesn't work.
#        globlastterm

        print -rn - "${esc_civis}"
        getcandidate
        typeset last_splitted="${g_splitted[$((${#g_splitted[*]} - 1))]}"
        typeset last_lextok="${g_lextoks[$((${#g_lextoks[*]} - 1))]}"
        ## if the name is longer than 80 chars the it just won't insert everything...
        ## in .sh.edchar. What to do?
        ##
        ## TODO: INSTEAD OF APPENDING IT'S REALLY SANER TO USE THE $'\b' CHARACTER
        ##       SO EVERYTHING WILL BE COHERENT. BUT THIS DOUBLES THE REQUIRED BUFFER
        ##       SIZE OF .sh.edchar. ANY OTHER SANE MECHANISMS TO USE OTHER THAN
        ##       .sh.edchar?
        ##
        ## BUG:  Try pressing TAB at
        ##
        ##       ls Calibre\ Library/calibre/News\ today\ \[fre,\ 04\ nov\ 2022\]\ \(154\)/
        ##
        ##       Instant failure.
        if [[ ${#g_result[*]} -eq 1 ]]; then
            typeset toadd="${g_result[0]}"
            toadd="${toadd#${last_splitted}}"
            quoteresult "${toadd}" "${last_lextok}" 0
            if [[ ! -z "${g_result[0]}" && ! "${g_result[0]}" = */ ]]; then
                .sh.edchar="${g_quoted} "
            else
                .sh.edchar="${g_quoted}"
            fi
            completed=2
        else
            ## Check if we have a "lowest common denominator". If yes, append. 
            commonpart
            typeset toadd="${g_common}"
            ## BUG: last_splitted is treated as pattern. How to force it to be only string?
            toadd="${toadd#${last_splitted}}"
            quoteresult "${toadd}" "${last_lextok}" 1
            .sh.edchar="${g_quoted}"
            completed=1
        fi
        fmtresult
        if (( completed <= 1 )); then
            cclear
            cshow "${g_view}"
            if ((completed == 0)) then;
               .sh.edchar=''
            fi
        else
            :;
            cclear
        fi
        # TODO: How to detect if the line is too long so we can call cclear? Calling PS1
        # should be okay but only if PS1 is idempotent. Plus escape sequences will pollute
        # the count. tput is the best but how to get cursor position from it?
#        if (( "${#.sh.edchar}" > 0 )); then
#            typeset testps1="$(PS1)"
#            if (( "${#.sh.edchar}" + "${#.sh.edtext}" + nps1 > "${COLUMNS}" )); then
#                cclear
#            fi
#        fi
    fi
    tput cnorm
    eval "${oldkeytrap}"
}
trap keytrap KEYBD
