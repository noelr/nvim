" Vim syntax file for floating command line
" Language: Floating Command Line
" Maintainer: Auto-generated

if exists("b:current_syntax")
  finish
endif

" Match command lines (non-indented, non-empty lines)
syntax match floatingcmdCommand "^\s\@!.*$"

" Match output lines (lines starting with two spaces)
syntax match floatingcmdOutput "^  .*$"

" Match error lines (lines containing Error:)
syntax match floatingcmdError "^  Error:.*$"

" Define default highlighting
hi def link floatingcmdCommand Statement
hi def link floatingcmdOutput Comment  
hi def link floatingcmdError ErrorMsg

let b:current_syntax = "floatingcmd"