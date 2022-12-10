# ksh93_autocmpt: Programmable autocompletion for ksh93

This program provides programmable autocompletion for the ksh93
shell. It uses `tput` to display completion result.

## Installation
Put the folder `ksh93_autocmpt` into `~/.local/share/` then source
`autocmpt.sh` in `~/.kshrc`.

## Writing an Extension

When the user presses `<TAB>` at a position that is not the
command and the current command in the input buffer is `THECMD` (for
example, `THECMD` can be `git` or `ssh`), the program searches in
`~/.local/share/ksh93_autocmpt/completors/` a file whose name matches the
pattern `(_|%)THECMD`; this file is called a "completor". A completor
should print a list of candidates to its standard output.

If a completor is executable, regardless of whether it is prefixed by
`_` or `%`, it will be executed in the following form:
```
<completor> <user_arg0> <user_arg1> <user_arg2> ...
```
where `<user_argN>` are the user's arguments from her input buffer that
appears before her cursor.
Otherwise, the completor is assumed to be a ksh script that 1) can be
sourced, 2) defines a function `_AUTOCMPT_DO`, and 3) do not leave any
other variables or functions defined after termination. The function
`_AUTOCMPT_DO` will be called in the same way to obtain a list of candidate,
explicity, in the following form
```
_AUTOCMPT_DO <user_arg0> <user_arg1> <user_arg2> ...
```

The difference is only that a sourced completor can access non-exported
variables and alias etc. in the user's shell but it ought to clean up itself;
while an executable one can only access exported variables, but it does not
need to `unset` any variables that it declares.

For example, if the user has the following in her input buffer:
```
$ git remote reblah
               ^
             CURSOR
```
and there is an executable file called `_git` then the completor wlll be called
as
```
_git git remote re
```

A completor should always output a list of candidates that are separated by the
ASCII character that is represented by ksh's `$'\a'`, in other words, the ASCII
charactor `0x07`.

If a completor's file name starts with a `_` it must output only candidates that
are prefixed by the to-be-completed argument that immediately preceeds the
user's cursor; while completors whose file names start with a `%` can output
any candidates, in which those that are not prefixed by the argument that
immediately preceeds the user's cursor will be automatically filtered away
before being displayed to the user. If the output of a `_`-prefixed completor
includes a candidate that does not satisfy the said condition, the behaviour of
the program is undefined.

Continuing the example, if the `git` completor is in a file named `_git` then it
may output `mote\amove` and if it were in `%git` it may output
`add\aclone\aremote\aremove`.

## Security Warning

This program contains sorcery that may not be safe
if your yet-to-be-completed input contains `$()` or backticks. It's still
probably much safer than zsh's default behaviour, which allows
all command substitution, but looser than bash's.

If your input buffer contains weird commands in `$()` or backticks that 1)
does not use anything in $PATH, 2) when evaluated in a restricted
sub-shell (which also implies no redirection allowed)
manage to find a way to change the state of the parent shell or that
of the OS's, then a <TAB> key will cause "side effect". Furthermore
if this weird command is also non-idempotent then the behaviour is
undefined.

That is, if you have a shell bomb in your input buffer you shouldn't
press `<TAB>`--but better, don't copy such thing into your terminal at
all.
