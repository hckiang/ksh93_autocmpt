# For ksh93

## ---------------------------------------------------------------------
##
##
##
##
##                         KSH93 AUTOCMPT.
##
##
##
##   Put the folder "ksh93_autocmpt" into ~/.local/share/
##   then source this script in ~/.kshrc.
##
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

[[ "${TERM}" == dumb || $- != *i* ]] && return

typeset -a _autocmpt_result
typeset -a _autocmpt_jailevaled
typeset -i _autocmpt_state=0
typeset -i _autocmpt_nline=0
typeset -a _autocmpt_closequotes
typeset -a _autocmpt_lextoks
typeset -i _autocmpt_ntok
typeset -a _autocmpt_tags
typeset -i _autocmpt_lextokgood _autocmpt_curonspace
typeset -i _autocmpt_xpos _autocmpt_ypos
typeset _autocmpt_quoted
typeset _autocmpt_common
typeset _autocmpt_view
typeset _autocmpt_oldps1get="`typeset -f PS1.get`"
typeset _autocmpt_oldkeytrap="$(trap -p KEYBD)"
typeset -A _autocmpt_completortypes=([A]='_-x' [B]='_! -x' [C]='%-x' [D]='%! -x')
typeset _autocmpt_completor=''

typeset _autocmpt_escsmcup="${ tput smcup 2>/dev/null ;}"
typeset _autocmpt_escrmcup="${ tput rmcup 2>/dev/null ;}"
typeset _autocmpt_escsc="${ tput sc 2>/dev/null ;}"
typeset _autocmpt_escrc="${ tput rc 2>/dev/null ;}"
typeset _autocmpt_esccivis="${ tput civis 2>/dev/null ;}"
typeset _autocmpt_esccnorm="${ tput cnorm 2>/dev/null ;}"   ## This one doesn't work?
typeset _autocmpt_esccuu9="${ tput cuu 9 2>/dev/null ;}"
typeset _autocmpt_escel="${ tput el 2>/dev/null ;}"
if [[ -z "${_autocmpt_escsmcup}" || \
      -z "${_autocmpt_escrmcup}" || \
      -z "${_autocmpt_escsc}"    || \
      -z "${_autocmpt_escrc}"    || \
      -z "${_autocmpt_esccivis}" || \
      -z "${_autocmpt_esccnorm}" || \
      -z "${_autocmpt_esccuu9}"  || \
      -z "${_autocmpt_escel}" ]]; then
   print 'ksh93_autocmpt: terminal not supported.' >&2
   return;
fi

[[ -z "$AUTOCMPT_ROOT" ]] && \
    AUTOCMPT_ROOT="$HOME/.local/share/ksh93_autocmpt"

function _autocmpt_xypos {
    "${AUTOCMPT_ROOT}"/curpos 3>&1 1>&2- 2>&3- | { \
        read -r -d $'\t' _autocmpt_xpos; read -r -d $'\0' _autocmpt_ypos; }
    [[ ! ( "$_autocmpt_xpos" = [0-9]+ && "$_autocmpt_ypos" = [0-9]+ && \
               ( ! "$_autocmpt_xpos" = 0 ) && ( ! "$_autocmpt_ypos" = 0 ) ) ]]
    return $?
}

## Turn off the entire thing if terminal aren't ANSI or doesn't have DSR
_autocmpt_xypos
if (( $? != 0 )); then
    print "Waited for about half a second but the terminal doesn't respond to Device Status Report. Turning off ksh93_autocmpt." >&2
    return;
fi


function _autocmpt_jaileval {
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

_autocmpt_closequotes[0]='\c';_autocmpt_closequotes[1]=\';_autocmpt_closequotes[2]='\"'
function _autocmpt_jailevalguess {
    typeset ocmd t
    typeset -a R
    typeset -i retval j k=0
    for ((j=0; j<${#_autocmpt_closequotes[*]}; ++j)); do
#        print '---' >&2
#        print "EVAL: >>${ printf "%s${_autocmpt_closequotes[j]}" "${1}";}<<" >&2
#        print '---' >&2
        ocmd="$( printf "%s${_autocmpt_closequotes[j]}" "${1}";)"
#        print "OCMD: >""$ocmd""<"
        _autocmpt_jaileval "${ocmd}" | { IFS=$'\a' read -r -A -d $'\0' R; read -r -d $'\0' t;}
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
##    _autocmpt_jesplit 'y z `pwd` `ls`/foo ${PWD}/bar'
##    printf '%s\n' _autocmpt_jailevaled[0] _autocmpt_jailevaled[1] _autocmpt_jailevaled[2] _autocmpt_jailevaled[3]
function _autocmpt_jesplit {  #If the last argument starts with a ' for example then it's just eliminated.
    typeset w
    typeset -i j=0
    set -A _autocmpt_jailevaled
    _autocmpt_jailevalguess "$1" | IFS=$'\a' read -r -d $'\0' -A _autocmpt_jailevaled
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

function _autocmpt_tokenize_lex {
    typeset x="$1" arg1="$1"
    typeset -i oi=0 lenorig="${#x}" ti=0 pt=0
    typeset rslt
    typeset ch
    x="${x} "
    set -A _autocmpt_lextoks
    set -A _autocmpt_tags
    _autocmpt_ntok=0
    _autocmpt_lextokgood=0
    _autocmpt_curonspace=0
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
            _autocmpt_jailevalguess "${x:$pt:$((oi-pt))}" | IFS=$'\a' read -r -d $'\0' -A rslt
#            print "JAILEVAL RSLT: >>${rslt}<<"
#            print "GSPLITED[TI]: ${_autocmpt_jailevaled[$ti]}"
            if [[ "${rslt[0]}" = "${_autocmpt_jailevaled[$ti]}" ]]; then
                _autocmpt_tags[$((ti++))]=$((oi-1))
                pt=$((oi+1))
            fi
            : $((oi++))
        fi
    done
    ## Have we gotten enough parameters?
#    print "N_AUTOCMPT_TAGS ${#_autocmpt_tags[*]} NGSPLITTED ${#_autocmpt_jailevaled[*]}"
    if [[ ${#_autocmpt_tags[*]} = ${#_autocmpt_jailevaled[*]} ]]; then
        pt=0;
        for ((i=0; i<${#_autocmpt_tags[*]}; ++i)); do
            _autocmpt_lextoks[$i]="${arg1:pt:((_autocmpt_tags[i]-pt+1))}"
            pt=$((_autocmpt_tags[i]+2))
        done
        if [[ ${_autocmpt_tags[$((i-1))]} -lt $((.sh.edcol - 1)) ]]; then
            _autocmpt_lextoks[$i]=''
            _autocmpt_jailevaled[$i]=''
            _autocmpt_curonspace=1
        else
            _autocmpt_curonspace=0
        fi
        _autocmpt_lextokgood=0
    else
        _autocmpt_lextokgood=1
    fi
    _autocmpt_ntok=${#_autocmpt_lextoks[*]}
}

function _autocmpt_show {
    typeset -i i="$(awk 'length>'${COLUMNS}'{c++} END{print c+NR}' <(print -r - "${1}"))"
    if (( i > LINES-2 )); then
        print -rn - "${_autocmpt_escsmcup}"
        _autocmpt_clear
        ## This asking isn't that straightforward... You can't override a keytrap here.
        ## So you'll need a new state.
        # print 'Display all '"${#_autocmp__autocmpt_result[*]} possibilities? (y/n) \c"
        print -rn - "${1}" | less  # More doesn't catch the Enter key for some reasons...?
        print -rn - "${_autocmpt_escrmcup}"
        return
    fi
    _autocmpt_nline=$i
    ## TODO: How to do \ED portably? \ED basically move the cursor down
    ##       WHILE scroll when needed WHILE remembering column position.
    printf $'\eD%.0s' {1..$i}
    print -rn - "${_autocmpt_esccuu9/9/${_autocmpt_nline}}""${_autocmpt_escsc}"$'\n'"${1}${_autocmpt_escrc}"
    _autocmpt_state=1
}
function _autocmpt_clear {
    typeset -i nostartshift=${1}
    typeset -i i=${_autocmpt_nline}
    print -rn - "${_autocmpt_escsc}"
    if (( nostartshift == 1 )); then
        : $((i--))
        print -rn - "${_autocmpt_escel}"
    fi
    while ((i-- > 0)); do
        print -rn $'\n'"${_autocmpt_escel}"
    done
    print -rn - "${_autocmpt_escrc}"
    _autocmpt_nline=0
    _autocmpt_state=0
}
function _autocmpt_absroot {
    cd "$(dirname "$1")"
    printf "%s/%s\n" "$(pwd)" "$(basename "$1")"
    cd "$OLDPWD"
}


function _autocmpt_getcandidate {
    typeset -i j=0
    typeset -i found=0
    typeset root completor_root file
    root="$(_autocmpt_absroot "${AUTOCMPT_ROOT}")"
    mkdir -p "${root}"
    completor_root="${root}/completors"

    # Check if the cursor is at the command itself. If yes, set the completor to the
    # command completor.
    if (( ${#_autocmpt_jailevaled[*]} == 1 )); then
        found=2
        file="${completor_root}/___CMD"
    fi

    if (( found == 0 )); then
        for typ in A B C D; do
            typeset def="${_autocmpt_completortypes[$typ]}"
            typeset prefix="${def:0:1}"
            typeset cond="${def:1:${#def}}"
            for file in "${completor_root}"/*; do
                if test "$(basename "$file")" = "${prefix}${_autocmpt_jailevaled[0]}" && test $cond "$file" ]]; then
                    found=$(('$typ'-'A'+1))
                    break;
                fi
            done
            if (( found != 0 )); then
                break
            fi
        done
    fi
    # _autocmpt_jailevaled doesn't match any completors. Try using the raw token?
    if (( found == 0 && _autocmpt_lextokgood == 0 )); then
        for file in "${completor_root}"/*; do
            if [[ "$(basename "$file")" = _"${_autocmpt_lextoks[0]}" && -x "$file" ]]; then
                found=1;
                break
            fi
        done
    fi
    # Use fallback if found nothing.
    if (( found == 0 )); then
        file="${completor_root}/___FALLBACK"
        found=19
    fi
    set -A _autocmpt_result
    _autocmpt_completor="$file"
    case "$found" in
        1*) "$_autocmpt_completor" "${_autocmpt_jailevaled[@]}" | IFS=$'\a' read -r -d $'\0' -A _autocmpt_result ;;
        2*)
            . "$_autocmpt_completor"
            _AUTOCMPT_DO "${_autocmpt_jailevaled[@]}" | IFS=$'\a' read -r -d $'\0' -A _autocmpt_result
            unset -f _AUTOCMPT_DO
            ;;
        *)
            typeset -a cand
            if (( found == 3 )); then
                "$_autocmpt_completor" "${_autocmpt_jailevaled[@]}" | IFS=$'\a' read -r -d $'\0' -A cand
            else
                . "$_autocmpt_completor"
                _AUTOCMPT_DO "${_autocmpt_jailevaled[@]}" | IFS=$'\a' read -r -d $'\0' -A cand
                unset -f _AUTOCMPT_DO
            fi
            j=0
            for x in ${cand[*]}; do
                [[ "$x" = "${_autocmpt_jailevaled[-1]}"* ]] && _autocmpt_result[$((j++))]="$x"
            done
            ;;
    esac

    # If a specialized completor doesn't say anything then fallback to file names
    if (( found < 10 && (${#_autocmpt_result[*]} == 0 ||
                             (${#_autocmpt_result[*]} == 1 && ${#_autocmpt_result[0]} == 0)) )); then
        _autocmpt_completor="${completor_root}/___FALLBACK"
        "$_autocmpt_completor" "${_autocmpt_jailevaled[@]}" | IFS=$'\a' read -r -d $'\0' -A _autocmpt_result
    fi
}
function _autocmpt_fmtresult {
    ## TODO: Should be more flexible, in particular, there are cases where / shouldn't be
    ## trimmed from viewing...
    if [[ "$(basename "$_autocmpt_completor")" = '___FALLBACK' && "$1" = 1 ]]; then
        typeset -a V
        typeset q
        typeset -i j
        for ((j=0; j<${#_autocmpt_result[*]}; ++j)); do
            # We can use base name instead but it's very, very slow for big folders.
            #            V[$j]="${ basename "${_autocmpt_result[$j]}";}"
            #            [[ -d "${_autocmpt_result[$j]}" ]] && V[$j]="${V[$j]}/"
            if [[ "${_autocmpt_result[$j]}" = */ ]]; then
                q="${_autocmpt_result[$j]:0:$((${#_autocmpt_result[$j]} - 1))}"
                V[$j]="${q##+(*\/)}/"
            else
                V[$j]="${_autocmpt_result[$j]##+(*\/)}"
            fi
        done
        _autocmpt_view="$(COLUMNS=$COLUMNS column <(printf "%s\n" "${V[@]}"))"
    else
        _autocmpt_view="$(COLUMNS=$COLUMNS column <(printf "%s\n" "${_autocmpt_result[@]}"))"
    fi
}

function _autocmpt_quoteresult {  ## Guess if user has hanging ', $', or " and adapt to it.
    if [[ -z "$1" ]]; then
        _autocmpt_quoted=''
    elif [[ -z "$2" ]]; then
        _autocmpt_barequoteresult "$1"
## The below patterns causes a miserably slow loop that needs to be killed with -9.
## But this regexp is wrong and useless anyway.
#    elif [[ "$2" = *(*)*(%(\'\'E\\)|%(\"\"Q\'E\\))\'*([^\']) ]]; then
    elif [[ "$2" = *([^\"\'])*(%(\'\'E\\)|%(\"\"Q\'E\\))*([^\'])\$\'*([^\']) ]]; then
        _autocmpt_open_dollarsinglequoteresult "$1" "$3"
    elif [[ "$2" = *([^\"\'])*(%(\'\'E\\)|%(\"\"Q\'E\\))*([^\'])\'*([^\']) ]]; then
        _autocmpt_open_singlequoteresult "$1" "$3"
    elif [[ "$2" = *([^\"\'])*(%(\'\'E\\)|%(\"\"Q\'E\\))*([^\"])\"*([^\"]) ]]; then
        _autocmpt_open_doublequoteresult "$1" "$3"
    else
        _autocmpt_barequoteresult "$1"
    fi
}

function _autocmpt_barequoteresult {
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
    typeset input22="${input21//:/\\\:}"
    _autocmpt_quoted="$input22"
}
function _autocmpt_open_singlequoteresult {
    typeset input0="$1"
    typeset input1="${input0//\'/\\\'}"
    # ASCII tabs won't work in .sh.edtext so we replace it.
    typeset input2="${input1//	/\'\$\'\\t\'\'}"
    _autocmpt_quoted="${input2}"
    (( $2 == 0 )) && _autocmpt_quoted="${_autocmpt_quoted}'"
}
function _autocmpt_open_dollarsinglequoteresult {
    typeset input0="$1"
    typeset input1="${input0//\'/\\\'}"
    typeset input2="${input1//\\/\\\\}"
    typeset input3="${input1//	/\\t}"
    _autocmpt_quoted="${input3}"
    (( $2 == 0 )) && _autocmpt_quoted="${_autocmpt_quoted}'"
}
function _autocmpt_open_doublequoteresult {
    typeset input0="$1"
    typeset input1="${input0//\"/\\\"}"
    typeset input2="${input1//\\/\\\\}"
    typeset input3="${input2//\`/\\\`}"
    typeset input4="${input3//\$/\\\$}"
    typeset input5="${input4//	/\"\$\'\\t\'\"}"
    # Escaping like "\!" doesn't work like normal. It's insane.
    typeset input6="${input5//\!/\"\\\!\"}"
    _autocmpt_quoted="${input6}"
    (( $2 == 0 )) && _autocmpt_quoted="${_autocmpt_quoted}\""
}


## Extract a prefixing part of matches that is common
function _autocmpt_commonpart {
    _autocmpt_common=''
    typeset c="${_autocmpt_result[0]:0:1}"
    typeset -i j k=0 finish=0 minl=0
    typeset -i ncand=${#_autocmpt_result[*]}
    minl="${#_autocmpt_result[0]}"
    for ((j=0; j<ncand; ++j)); do
        [[ $minl -gt ${#_autocmpt_result[$j]} ]] && minl=${#_autocmpt_result[$j]}
    done
    while ((finish == 0 && k < minl)); do
        for ((j=1; j<ncand; ++j)); do
            if [[ ! "${_autocmpt_result[j]:k:1}" = "$c"*(*) ]];then
               finish=1
               break;
            fi
        done
        ## If it's gone this far, and not yet done, c is in the common
        if (( finish == 0 )); then
            _autocmpt_common="${_autocmpt_common}${c}"
            : $((++k))
            c="${_autocmpt_result[0]:k:1}"
        else
            : $((++k))
        fi
    done
}
function _autocmpt_globlastterm {
    ## If the last term has a successful glob then fill _autocmpt_result with globbed list
    typeset -i j=0, allsame=1, same=1
    typeset -a noglobresult
    typeset OLDIFS="$IFS"
    set -o noglob
    set +o braceexpand
    ## Need to restrict field splitting, otherwise the loop won't glob correctly if
    ## there were spaces.
    IFS=$'\0'
    for x in ${_autocmpt_jailevaled[-1]}; do
#        print ">>$x<<"
        noglobresult[$((j++))]="$x"
    done
    set +o noglob
    set -o braceexpand
#    if (( j > 1 )); then
#        set -A _autocmpt_result
#        return 1;
#    fi
    j=0
    set -A _autocmpt_result
    for x in ${_autocmpt_jailevaled[-1]}; do
        _autocmpt_result[$j]="$x"
#        print ">>$x<<" ">>${noglobresult[$j]}<<" 
#        print "SAME=" $( ! [[ "$x" = "${noglobresult[$j]}" ]]; print -n - $?; )
        same=$( [[ ! "$x" = "${noglobresult[$j]}" ]]; print -n - $?; )
        : $((allsame = allsame * same, ++j))
    done
    IFS="$OLDIFS"
    ## Detect failed glob... If the non-glob and globbed are the same and files don't exist
    ## then it's a file glob.
    if (( ${#noglobresult[*]} <= 0 || (${#noglobresult[*]} == ${#_autocmpt_result[*]} && (allsame == 1)) )); then
#        print not_globbed $j ${#noglobresult[*]} ${#_autocmpt_result[*]}  $allsame
        set -A _autocmpt_result
        return 1;
    else
#        print globbed $j ${#noglobresult[*]} ${#_autocmpt_result[*]}  $allsame
        return 0;
    fi
}
function _autocmpt_depattern {
    typeset str0="$1"
    typeset str1="${str0//\[/\\\[}"
    typeset str2="${str1//\]/\\\]}"
    typeset str3="${str2//\(/\\\(}"
    typeset str4="${str3//\)/\\\)}"
    typeset str5="${str4//\*/\\\*}"
    typeset str6="${str5//\?/\\\?}"
    print -r -n - "$str6"
}
function _autocmpt_keytrap {
    typeset -i completed=0 globexit=0 usedhiddenstar=0 regurgitated=0 showmode=0 trimdir=1 hiddenstar_regurg=0
    if (( _autocmpt_state = 1 )); then
        print -rn - "${_autocmpt_esccivis}"
    fi
    if [[ "${.sh.edchar}" = $'\n' || "${.sh.edchar}" = $'\r' || \
              "${.sh.edchar}" = $'\f' ]]; then
        print -rn - "${_autocmpt_esccivis}"
        _autocmpt_clear
    fi
    if [[ "${.sh.edchar}" = $'\t' ]]; then
        _autocmpt_jesplit "${.sh.edtext:0:${.sh.edcol}}"
        _autocmpt_tokenize_lex "${.sh.edtext:0:${.sh.edcol}}"
        if (( ${#_autocmpt_jailevaled[*]} == 0 || _autocmpt_lextokgood == 1 )); then
            .sh.edchar=''
            tput cnorm
            return
        fi
        print -rn - "${_autocmpt_esccivis}";
        _autocmpt_globlastterm
        globexit=$?
        if (( globexit > 0 )); then           ## Failed glob. Use completors instead.
            _autocmpt_getcandidate
#            print ${#_autocmpt_result[*]} ">>${_autocmpt_result[0]}<<"
            if (( (${#_autocmpt_result[*]} == 0 || (${#_autocmpt_result[*]} == 1 && ${#_autocmpt_result[0]} == 0)) )); then
                # If there still aren't candidates, append * to the end and glob again.
                _autocmpt_jailevaled[$((${#_autocmpt_jailevaled[*]} - 1))]="${_autocmpt_jailevaled[$((${#_autocmpt_jailevaled[*]} - 1))]}"'*'
                _autocmpt_lextoks[$((${#_autocmpt_lextoks[*]} - 1))]="${_autocmpt_lextoks[$((${#_autocmpt_lextoks[*]} - 1))]}"'*'
                usedhiddenstar=1
                _autocmpt_globlastterm
                globexit=$?
                # If *-appended glob works, regurgitate it to completor.
                if (( globexit == 0 && ${#_autocmpt_result[*]} == 1 && ${#_autocmpt_result[0]} != 0 )); then
                    ## Regurgitate to completor as usual.
                    hiddenstar_regurg=1
                    typeset tmpstr
                    _autocmpt_jailevaled[-1]="${_autocmpt_result[0]}"
                    set -A _autocmpt_result
                    _autocmpt_getcandidate
                    ## Remove the star trailing star to avoid confusing later sole-completion filling
                    tmpstr="${_autocmpt_jailevaled[$((${#_autocmpt_jailevaled[*]} - 1))]}"
                    _autocmpt_jailevaled[$((${#_autocmpt_jailevaled[*]} - 1))]="${tmpstr%\*}"
                    tmpstr="${_autocmpt_lextoks[$((${#_autocmpt_lextoks[*]} - 1))]}"
                    _autocmpt_lextoks[$((${#_autocmpt_lextoks[*]} - 1))]="${tmpstr%\*}"
                fi
            fi
        ## TODO: should I check if _autocmpt_result is empty, and #_autocmpt_result[*] == 0?
        elif (( ${#_autocmpt_result[*]} == 1 )); then ## Successful but single-result glob. Regurgitate.
            regurgitated=1
            _autocmpt_jailevaled[-1]="${_autocmpt_result[0]}"
            set -A _autocmpt_result
            _autocmpt_getcandidate
        fi

        typeset last_splitted="${_autocmpt_jailevaled[-1]}";
        typeset last_lextok="${_autocmpt_lextoks[-1]}";
        ## if the name is longer than 80 chars the it just won't insert everything...
        ## in .sh.edchar. What to do?
        ##
        ## TODO: INSTEAD OF APPENDING IT'S REALLY SANER TO USE THE $'\b' CHARACTER
        ##       SO EVERYTHING WILL BE COHERENT. BUT THIS DOUBLES THE REQUIRED BUFFER
        ##       SIZE OF .sh.edchar. ANY OTHER SANE MECHANISMS TO USE OTHER THAN
        ##       .sh.edchar?
        ##
#        print '\n' $globexit $usedhiddenstar $regurgitated >&2
#        print '\n' ">>${_autocmpt_result[0]}<<"
        if (( globexit != 0 || hiddenstar_regurg == 1 || regurgitated == 1 )); then
            ## If the result came from an completor...
            if (( ${#_autocmpt_result[*]} == 1 )); then  ## Single result.
                typeset toadd
                if (( usedhiddenstar == 0 )); then
                    toadd="${_autocmpt_result[0]}"
                    _autocmpt_depattern "${last_splitted}" | IFS= read -d $'\0' -r depat
#                    print - "->${toadd}<-" "->${depat}<-"
                    toadd="${toadd#${depat}}"
#                    print $'\n'">>${toadd}<< >>${last_lextok}<< >>${last_splitted}<<"
                    _autocmpt_quoteresult "${toadd}" "${last_lextok}" 0
                    showmode=0
                else
                    ## If we needed hidden star and subsequently regurgitated to file
                    ## completor and we got a sole result, then the sole-result
                    ## substitution isn't reliable anymore. Append a star and show
                    ## user what it has globbed instead.
                    if [[ "${_autocmpt_result[0]}" = */ ]]; then
                        _autocmpt_quoted=\*/
                    else
                        _autocmpt_quoted=\*
                    fi
                    showmode=1
                fi
                if [[ ! -z "${_autocmpt_result[0]}" && ! "${_autocmpt_result[0]}" = */ ]]; then
                    .sh.edchar="${_autocmpt_quoted} "
                else
                    .sh.edchar="${_autocmpt_quoted}"
                fi
            elif (( ${#_autocmpt_result[*]} >= 1 )); then
                ## Check if we have a "lowest common denominator". If yes, append.
                _autocmpt_commonpart
                typeset toadd="${_autocmpt_common}"
                _autocmpt_depattern "${last_splitted}" | IFS= read -d $'\0' -r depat
                toadd="${toadd#${depat}}"
                _autocmpt_quoteresult "${toadd}" "${last_lextok}" 1
                .sh.edchar="${_autocmpt_quoted}"
                showmode=1
            fi
        else
            ## If result is from a glob, don't complete the sole candidate but
            ## append a slash if there is a single glob that ends with a slash.
            ## unless it's from a hidden star, in which case the normal procedure
            ## applies.
            if (( ${#_autocmpt_result[*]} == 1 && ${#_autocmpt_result[0]} != 1 )); then
                if [[ "${_autocmpt_result[0]}" = */ && ! "${last_lextok}" = */ ]]; then
                    .sh.edchar="/"
                elif [[ -f "${_autocmpt_result[0]}" ]]; then
                    .sh.edchar=" "
                fi
            fi
            showmode=1
        fi
        if (( globexit == 0 || usedhiddenstar == 1 )); then
            trimdir=0
        fi
        case "$showmode" in
            0) ## No show
                _autocmpt_clear
                ;;
            1) ## Show reshow from _autocmpt_fmtresult _autocmpt_view
                _autocmpt_fmtresult ${trimdir}
                _autocmpt_clear
                _autocmpt_show "${_autocmpt_view}"
                if [[ "${.sh.edchar}" = $'\t' ]]; then
                    .sh.edchar=''
                fi
                ;;
            *)
                if [[ "${.sh.edchar}" = $'\t' ]]; then
                    .sh.edchar=''
                fi
        esac
    else                        # Key is not \t
        # I am assuming the new key is at most two character. Otherwise the math will be
        # insane because noone knows what ksh or the users' own key trap will do with
        # the stuff in .sh.char... A more "sterile" approach might be to call the user's
        # oldkeytrap first then calculate the unicode width; but then escape sequences etc
        # will need to be taken care of. I think that's a bit overkill.
        _autocmpt_xypos
        (( $? == 0 && $_autocmpt_ypos == COLUMNS - 1 || $_autocmpt_ypos == COLUMNS )) && \
            _autocmpt_clear
    fi
    tput cnorm
    eval "${_autocmpt_oldkeytrap}"
}

trap _autocmpt_keytrap KEYBD

function PS1.get {
    if (( _autocmpt_state == 1 )); then
        print -rn - "${_autocmpt_escel}"
        _autocmpt_clear 1
    fi
    eval "${_autocmpt_oldps1get/PS1\.get/_autocmpt_oldps1getwrap}"
    [[ "$(typeset -f _autocmpt_oldps1getwrap)" == *_autocmpt_oldps1getwrap* ]] &&\
        _autocmpt_oldps1getwrap
}
