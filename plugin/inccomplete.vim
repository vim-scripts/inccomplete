" Name:          inccomplete
" Author:        xaizek (xaizek@gmail.com)
" Version:       1.1.7
"
" Description:   This is a completion plugin for C/C++/ObjC/ObjC++ preprocessors
"                include directive. It can be used along with clang_complete
"                (http://www.vim.org/scripts/script.php?script_id=3302) plugin.
"                And maybe with some others that I haven't tested.
"
"                It can complete both "" and <> forms of #include.
"                For "" it gets all header files in the current directory (so
"                it's assumed that you have something similar to
"                autocmd BufEnter,BufWinEnter * lcd %:p:h
"                in your .vimrc).
"                And for <> it gets all files that have hpp or h extensions or
"                don't have any.
"
" Configuration: g:inccomplete_findcmd - command to run GNU find program
"                default: 'find'
"                Note: On Windows you need to have Cygwin installed and to set
"                      full path to find utility. For example, like this:
"                      let g:inccomplete_findcmd = 'c:/cygwin/bin/find'
"                      Or it can be any find utility that accepts the following
"                      parameters and multiple search paths:
"                      -maxdepth 1 -type f
"
" ToDo:          - Maybe 'path' option should be replaced with some global
"                  variable like g:inccomplete_incpath?
"                - Is it possible to do file searching using only VimL?
"                - Maybe '.' in path should be automatically replaced with the
"                  path to current buffer instead of assuming that working
"                  directory is correct?

if exists("g:loaded_inccomplete")
    finish
endif

let g:loaded_inccomplete = 1

if !exists('g:inccomplete_findcmd')
    let g:inccomplete_findcmd = 'find'
endif

autocmd FileType c,cpp,objc,objcpp call s:ICInit()

" maps < and ", sets 'omnifunc'
function! s:ICInit()
    inoremap <expr> <buffer> < ICCompleteInc('<')
    inoremap <expr> <buffer> " ICCompleteInc('"')

    " save current 'omnifunc'
    let l:curbuf = fnamemodify(bufname('%'), ':p')
    if !exists('s:oldomnifuncs')
        let s:oldomnifuncs = {}
    endif
    let s:oldomnifuncs[l:curbuf] = &omnifunc

    setlocal omnifunc=ICComplete
endfunction

" checks whether we need to do completion after < or " and starts it when we do
" a:char is '<' or '"'
function! ICCompleteInc(char)
    if getline('.') !~ '^\s*#\s*include\s*$'
        return a:char
    endif
    return a:char."\<c-x>\<c-o>"
endfunction

" this is the 'completefunc'
function! ICComplete(findstart, base)
    let l:curbuf = fnamemodify(bufname('%'), ':p')
    if a:findstart
        if getline('.') !~ '^\s*#\s*include\s*\%(<\|"\)'
            let s:passnext = 1
            if !has_key(s:oldomnifuncs, l:curbuf)
                return col('.') - 1
            endif
            return eval(s:oldomnifuncs[l:curbuf]
                      \ ."(".a:findstart.",'".a:base."')")
        else
            let s:passnext = 0
            return match(getline('.'), '<\|"') + 1
        endif
    else
        if s:passnext == 1 " call previous 'completefunc' when needed
            if !has_key(s:oldomnifuncs, l:curbuf)
                return []
            endif
            let l:retval = eval(s:oldomnifuncs[l:curbuf]
                             \ ."(".a:findstart.",'".a:base."')")
            return l:retval
        endif
        let l:comlst = []
        let l:pos = match(getline('.'), '<\|"')
        let l:bracket = getline('.')[l:pos : l:pos]
        if l:bracket == '<'
            let l:bracket = '>'
        endif
        let l:completebraket = len(getline('.')) == l:pos + 1
        let l:inclst = s:ICGetCachedList(l:bracket == '"')
        for l:increc in l:inclst
            if l:increc[1] =~ '^'.a:base
                let l:item = {
                            \ 'word': l:increc[1],
                            \ 'menu': l:increc[0],
                            \ 'dup': 1,
                            \ }
                if l:completebraket
                    let l:item['word'] .= l:bracket
                endif
                call add(l:comlst, l:item)
            endif
        endfor
        return l:comlst
    endif
endfunction

" handles cache for <>-includes
function! s:ICGetCachedList(user)
    if a:user != 0
        return s:ICGetList(a:user)
    else
        let l:path = &path
        if exists('b:clang_user_options')
            let l:path .= b:clang_user_options
        endif
        if !exists('b:ICcachedinclist') || b:ICcachedpath != l:path
            let b:ICcachedinclist = s:ICGetList(a:user)
            let b:ICcachedpath = l:path
        endif
        return b:ICcachedinclist
    endif
endfunction

" searches for files that can be included in path
" a:user determines search area, when it's not zero look only in '.', otherwise
" everywhere in path except '.'
function! s:ICGetList(user)
    let l:pathlst = s:ICAddNoDups(split(&path, ','), s:ICGetClangIncludes())
    let l:pathlst = reverse(sort(l:pathlst))
    if a:user == 0
        call filter(l:pathlst, 'v:val != "" && v:val !~ "^\.$"')
        let l:iregex = ' -iregex '.shellescape('.*/[_a-z0-9]+\(\.hpp\|\.h\)?$')
    else
        call filter(l:pathlst, 'v:val != "" && v:val =~ "^\.$"')
        let l:iregex = ' -iregex '.shellescape('.*\(\.hpp\|\.h\)$')
    endif
    " substitute in the next command is for Windows (it removes back slash in
    " \" sequence, that can appear after escaping the path)
    let l:substcmd = 'substitute(shellescape(v:val), ''\(.*\)\\\"$'','
                              \ .' "\\1\"", "")'
    let l:pathstr = join(map(copy(l:pathlst), l:substcmd), ' ')
    let l:found = system(g:inccomplete_findcmd.' '
                       \ .l:pathstr
                       \ .' -maxdepth 1 -type f'.l:iregex)
    let l:foundlst = split(l:found, '\n')
    unlet l:found " to free some memory
    " prepare l:pathlst by forming regexps
    for l:i in range(len(l:pathlst))
        let l:tmp = substitute(l:pathlst[i], '\', '/', 'g')
        let l:pathlst[i] = [l:pathlst[i], '^'.escape(l:tmp, '.')]
    endfor
    let l:result = []
    for l:file in l:foundlst
        let l:file = substitute(l:file, '\', '/', 'g')
        for l:incpath in l:pathlst " find appropriate path
            if l:file =~ l:incpath[1]
                let l:left = l:file[len(l:incpath[0]):]
                if l:left[0] == '/' || l:left[0] == '\'
                    let l:left = l:left[1:]
                endif
                call add(l:result, [l:incpath[0], l:left])
                break
            endif
        endfor
    endfor
    return sort(l:result)
endfunction

" retrieves include directories from b:clang_user_options and
" g:clang_user_options
function! s:ICGetClangIncludes()
    if !exists('b:clang_user_options') || !exists('g:clang_user_options')
        return []
    endif
    let l:lst = split(b:clang_user_options.' '.g:clang_user_options, ' ')
    let l:lst = filter(l:lst, 'v:val !~ "\C^-I"')
    let l:lst = map(l:lst, 'v:val[2:]')
    return l:lst
endfunction

" adds one list to another without duplicating items
function! s:ICAddNoDups(lista, listb)
    let l:result = []
    for l:item in a:lista + a:listb
        if index(l:result, l:item) == -1
            call add(l:result, l:item)
        endif
    endfor
    return l:result
endfunction

" vim: set foldmethod=syntax foldlevel=0 :
