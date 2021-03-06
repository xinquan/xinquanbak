"=============================================================================
" File:        indexer.vim
" Author:      Dmitry Frank (dimon.frank@gmail.com)
" Version:     4.04
"=============================================================================
" See documentation in accompanying help file
" You may use this code in whatever way you see fit.


"TODO:
"
"   *) Если есть проекты с одинаковым названием - нужно показывать варнинг
"   *) Проверять версию ctags при старте:
"
"        во-первых, нужно выдавать error, если ctags вообще не установлен.
"
"        во-вторых, х3, нужно выдавать варнинг, если ctags не пропатчен.
"           чтобы не надоедать юзеру, если он все равно не хочет патчить, 
"           нужно сделать возможность убрать этот варнинг.
"           Пока что только приходит в голову сделать специальную опцию
"           для заглушивания этого варнинга.
"
"
" ----------------
"  In 3.0
"
" Опцию типа "менять рабочую директорию при смене проекта", и менять ее только
" в том случае, если проект сменили, а не только файл.
"
" ----------------
"
" *) !!! Unsorted tags file is BAD. Please try to make SED work with sorted
"    tags file.
"
" *) test on paths with spaces, both on Linux and Windows
" *) test with one .vimprojects and .indexer_files file, define projectName
" *) rename indexer_ctagsDontSpecifyFilesIfPossible to indexer_ctagsUseDirs or
"    something
" *) make #pragma_index_none,
"         #pragma_index_dir,
"         #pragma_index_files
" *) ability to define one file in .indexer_files
" *) maybe checking whether or not ctags is version 5.8.1
" *) maybe checking whether or not sed is present
" *) maybe checking whether or not sed is correctly parsing ( \\\\ or \\ )
"



" --------- MAIN INDEXER VARIABLES ---------
"
" s:dProjFilesParsed - DICTIONARY with info about files ".vimprojects" and/or ".indexer_files"
"     [  <path_to__indexer_files_or__vimprojects>  ] - DICTIONARY KEY, example of key:
"                                                      "_home_user__indexer_files"
"        ["projects"] - DICTIONARY
"           [  <project_name>  ] - DICTIONARY KEY
"              ["pathsRoot"]
"              ["pathsForCtags"]
"              ["not_exist"]
"              ["files"]
"              ["paths"]
"        ["filename"] = (for example) "/home/user/.indexer_files"
"        ["type"] - "IndexerFile" or "ProjectFile"
"        ["sVimprjKey"] - key for g:vimprj#dRoots
"
"
"
" s:sLastCtagsCmd    - last executed ctags command
" s:sLastCtagsOutput - output for last executed ctags command
"
" s:dCtagsInfo - DICTIONARY
"     ["executable"] - name of executable. For example, "ctags" or
"                      "ctags.exe", etc
"     ["versionOutput"] - output for ctags --version
"     ["boolCtagsExists"] - if ctags is found, then 1. Otherwise 0.
"     ["boolPatched"] - if version ctags is patched by Dmitry Frank, then 1.
"                       Otherwise 0.
"     ["versionFirstLine"] - output for ctags --version, but first line only.
"
"
" TODO: move this description to vimprj plugin
"
" g:vimprj#dRoots - DICTIONARY with info about $INDEXER_PROJECT_ROOTs
"     [  <$INDEXER_PROJECT_ROOT>  ] - DICTIONARY KEY
"        ["cd_path"] - path for CD. Can't be empty.
"        ["proj_root"] - $INDEXER_PROJECT_ROOT. Can be empty (for "default")
"        ["path"] - path to .vimprj dir. Actually, this is
"                   "proj_root"."/.vimprj", if "proj_root" isn't empty.
"        ["mode"] - "IndexerFile" or "ProjectFile"
"        ..... - many indexer options like "indexerListFilename", etc.
"
"
" g:vimprj#dFiles - DICTIONARY with info about all regular files
"     [  <bufnr('%')>  ] - DICTIONARY KEY
"        ["sVimprjKey"] - key for g:vimprj#dRoots
"        ["projects"] - LIST 
"                             NOTE!!!
"                             At this moment only ONE project
"                             is allowed for each file
"           [0, 1, 2, ...] - LIST KEY. At this moment, only 0 is available
"              ["file"] - key for s:dProjFilesParsed
"              ["name"] - name of project
"           

"        
"  

if v:version < 700
   call confirm("indexer error: You need Vim 7.0 or higher")
   finish
endif

try
   call vimprj#init()
catch
   " no vimprj plugin installed
endtry

let s:iVimprj_min_version = 102

if !exists("g:vimprj#version") || g:vimprj#version < s:iVimprj_min_version
   call confirm("Indexer error: since Indexer version 4.0 you need for plugin 'vimprj' version ".s:iVimprj_min_version." to be installed.")
   finish
endif

let g:iIndexerVersion = 404
let g:loaded_indexer  = 1


" ************************************************************************************************
"                                          VIMPRJ HOOKS
" ************************************************************************************************

function! <SID>SetTagsAndPath(iFileNum, sVimprjKey)
   for l:lFileProjs in g:vimprj#dFiles[ a:iFileNum ]["projects"]
      exec "set tags+=". s:dProjFilesParsed[ l:lFileProjs.file ]["projects"][ l:lFileProjs.name ]["tagsFilenameEscaped"]
      if g:vimprj#dRoots[ a:sVimprjKey ]['indexer']["handlePath"]
         exec "set path+=".s:dProjFilesParsed[ l:lFileProjs.file ]["projects"][ l:lFileProjs.name ]["sPathsAll"]
      endif
   endfor
endfunction

function! g:vimprj#dHooks['ApplySettingsForFile']['indexer'](dParams)
   " для каждого проекта, в который входит файл, добавляем tags и path
   let l:sVimprjKey = vimprj#getVimprjKeyOfFile( a:dParams['iFileNum'] )

   call <SID>SetTagsAndPath(a:dParams['iFileNum'], l:sVimprjKey)

endfunction

function! g:vimprj#dHooks['OnTakeAccountOfFile']['indexer'](dParams)
   let g:vimprj#dFiles[ a:dParams['iFileNum'] ]['projects'] = []
endfunction

function! g:vimprj#dHooks['NeedSkipBuffer']['indexer'](dParams)
   let l:sFilename = <SID>BufName(a:dParams['iFileNum'])
   " skip standard .vimprojects file
   if strpart(l:sFilename, strlen(l:sFilename)-12) == '.vimprojects'
      return 1
   endif

   " skip specified projecs file (g:indexer_projectsSettingsFilename)
   if exists("g:vimprj#sCurVimprjKey")
      if l:sFilename == a:dParams['dVimprjRootParams'].projectsSettingsFilename
         return 1
      endif
   endif

   return 0

endfunction

" Этот хук запускается, когда открыт новый файл.
"
" К тому времени, как этот хук запускается, плагин vimprj
" уже сделал следующее:
"     ищем директорию .vimprj
"     если нашли, то:
"        запускаем хук SetDefaultOptions
"        выполняем все *.vim файлы из .vimprj
"        меняем текущую директорию
"        если этой директории .vimprj еще нет в нашей базе,
"           то добавляем ее туда (хук OnAddNewVimprjRoot)
"
function! g:vimprj#dHooks['OnFileOpen']['indexer'](dParams)
   "function! <SID>OnFileOpen()

   " выясняем, какой файл проекта нужно юзать
   " смотрим: еще не парсили этот файл? (dProjFilesParsed)
   "    парсим
   " endif

   let l:sVimprjKey = vimprj#getVimprjKeyOfFile( a:dParams['iFileNum'] )
   let l:iFileNum   = a:dParams['iFileNum']

   "let l:sVimprjKey = g:vimprj#sCurVimprjKey
   "let l:iFileNum   = g:vimprj#iCurFileNum

   " $INDEXER_PROJECT_ROOT can appear in .vimprojects or .indexer_files.
   " we should define it
   let $INDEXER_PROJECT_ROOT = g:vimprj#dRoots[ l:sVimprjKey ].proj_root





   let l:sVimprjDirName = g:vimprj#dRoots[ l:sVimprjKey ].path
   let l:iLen = strlen(l:sVimprjDirName)

   let l:boolPreferIndexerFile = (strpart(a:dParams['dVimprjRootParams'].indexerListFilename,      0, l:iLen) == l:sVimprjDirName)
   let l:boolPreferProjectFile = (strpart(a:dParams['dVimprjRootParams'].projectsSettingsFilename, 0, l:iLen) == l:sVimprjDirName)

   if !empty(l:sVimprjDirName)
            \  && filereadable(a:dParams['dVimprjRootParams'].indexerListFilename)
            \  && filereadable(a:dParams['dVimprjRootParams'].projectsSettingsFilename)
            \  && (!l:boolPreferIndexerFile || !l:boolPreferProjectFile)
            \  && ( l:boolPreferIndexerFile ||  l:boolPreferProjectFile)

      if l:boolPreferIndexerFile
         let a:dParams['dVimprjRootParams'].mode = 'IndexerFile'
      elseif l:boolPreferProjectFile
         let a:dParams['dVimprjRootParams'].mode = 'ProjectFile'
      endif

   elseif (filereadable(a:dParams['dVimprjRootParams'].indexerListFilename))
      " read all projects from proj file
      let a:dParams['dVimprjRootParams'].mode = 'IndexerFile'

   elseif (filereadable(a:dParams['dVimprjRootParams'].projectsSettingsFilename))
      " read all projects from indexer file
      let a:dParams['dVimprjRootParams'].mode = 'ProjectFile'

   else
      let a:dParams['dVimprjRootParams'].mode = ''
   endif

   if     a:dParams['dVimprjRootParams'].mode == 'IndexerFile'
      let l:sProjFilename = a:dParams['dVimprjRootParams'].indexerListFilename
   elseif a:dParams['dVimprjRootParams'].mode == 'ProjectFile'
      let l:sProjFilename = a:dParams['dVimprjRootParams'].projectsSettingsFilename
   else
      let l:sProjFilename = ''
   endif


   let l:sProjFileKey = <SID>GetKeyFromPath(l:sProjFilename)

   if (l:sProjFileKey != "") " если нашли файл с описанием проектов
      if (!exists("s:dProjFilesParsed['".l:sProjFileKey."']"))
         " если этот файл еще не обрабатывали
         let s:dProjFilesParsed[ l:sProjFileKey ] = {
                     \     "filename"   : l:sProjFilename,
                     \     "type"       : a:dParams['dVimprjRootParams'].mode,
                     \     "sVimprjKey" : l:sVimprjKey,
                     \     "projects"   : {},
                     \  }

         call <SID>ParseProjectSettingsFile(l:sProjFileKey)

         " добавляем autocmd BufWritePost для файла с описанием проекта

         augroup Indexer_SavPrjFile
            "let l:sPrjFile = substitute(s:dProjFilesParsed[ l:sProjFileKey ]["filename"], '^.*[\\/]\([^\\/]\+\)$', '\1', '')
            let l:sPrjFile = substitute(s:dProjFilesParsed[ l:sProjFileKey ]["filename"], ' ', '\\\\\\ ', 'g')
            exec 'autocmd Indexer_SavPrjFile BufWritePost '.l:sPrjFile.' call <SID>UpdateTagsForEveryNeededProjectFromFile(<SID>GetKeyFromPath(expand("<afile>:p")))'
         augroup END


      endif

      "
      " Если пользователь не указал явно, какой проект он хочет проиндексировать,
      " ( опция g:indexer_projectName )
      " то
      " надо выяснить, какие проекты включать в список проиндексированных.
      " тут два варианта: 
      " 1) мы включаем проект, если открытый файл находится в
      "    любой его поддиректории
      " 2) мы включаем проект, если открытый файл прямо указан 
      "    в списке файлов проекта
      "    
      " есть опция: g:indexer_enableWhenProjectDirFound, она прямо указывает,
      "             нужно ли включать любой файл из поддиректории, или нет.
      "             Но еще есть опция g:indexer_ctagsDontSpecifyFilesIfPossible, и если
      "             она установлена, то плагин вообще не знает ничего про 
      "             конкретные файлы, поэтому мы должны себя вести также, какой
      "             если установлена первая опция.
      "
      " Еще один момент: если включаем проект только если открыт файл именно
      "                  из этого проекта, то просто сравниваем имя файла 
      "                  со списком файлов из проекта.
      "
      "                  А вот если включаем проект, если открыт файл из
      "                  поддиректории, то нужно еще подниматься вверх по дереву,
      "                  т.к. может оказаться, что директория, в которой
      "                  находится открытый файл, является поддиректорией
      "                  проекта, но не перечислена явно в файле проекта.
      "
      "
      if (a:dParams['dVimprjRootParams'].projectName == '')
         " пользователь не указал явно название проекта. Нам нужно выяснять.

         let l:iProjectsAddedCnt = 0
         let l:lProjects = []
         if (a:dParams['dVimprjRootParams'].enableWhenProjectDirFound || <SID>_UseDirsInsteadOfFiles(a:dParams['dVimprjRootParams']))
            " режим директорий
            for l:sCurProjName in keys(s:dProjFilesParsed[ l:sProjFileKey ]["projects"])
               let l:boolFound = 0
               let l:i = 0
               let l:sCurPath = ''
               while (!l:boolFound && l:i < 10)
                  "let l:tmp = input(simplify(expand('%:p:h').l:sCurPath)."====".join(s:dProjFilesParsed[ l:sProjFileKey ]["projects"][l:sCurProjName].paths, ', '))
                  if (<SID>IsFileExistsInList(s:dProjFilesParsed[ l:sProjFileKey ]["projects"][l:sCurProjName].paths, expand('%:p:h').l:sCurPath))
                     " user just opened file from subdir of project l:sCurProjName. 
                     " We should add it to result lists

                     if l:iProjectsAddedCnt == 0
                        call <SID>AddNewProjectToCurFile(l:sProjFileKey, l:sCurProjName, l:iFileNum)
                     endif
                     let l:iProjectsAddedCnt = l:iProjectsAddedCnt + 1
                     call add(l:lProjects, l:sCurProjName)
                     break
                  endif
                  let l:i = l:i + 1
                  let l:sCurPath = l:sCurPath.'/..'
               endwhile
            endfor

            if (l:iProjectsAddedCnt > 1)
               echoerr "Warning: directory '".simplify(expand('%:p:h'))."' exists in several projects: '".join(l:lProjects, ', ')."'. Only first is indexed."
               "let l:tmp = input(" ")
            endif


         else
            " режим файлов
            for l:sCurProjName in keys(s:dProjFilesParsed[ l:sProjFileKey ]["projects"])
               if (<SID>IsFileExistsInList(s:dProjFilesParsed[ l:sProjFileKey ]["projects"][l:sCurProjName].files, expand('%:p')))
                  " user just opened file from project l:sCurProjName. We should add it to
                  " result lists

                  if l:iProjectsAddedCnt == 0
                     call <SID>AddNewProjectToCurFile(l:sProjFileKey, l:sCurProjName, l:iFileNum)
                  endif
                  let l:iProjectsAddedCnt = l:iProjectsAddedCnt + 1
                  call add(l:lProjects, l:sCurProjName)

               endif
            endfor

            if (l:iProjectsAddedCnt > 1)
               echoerr "Warning: file '".simplify(expand('%:t'))."' exists in several projects: '".join(l:lProjects, ', ')."'. Only first is indexed."
               "let l:tmp = input(" ")
            endif

         endif

      else    " if projectName != ""
         " пользователь явно указал проект, который нужно проиндексировать
         for l:sCurProjName in keys(s:dProjFilesParsed[ l:sProjFileKey ]["projects"])
            if (l:sCurProjName == a:dParams['dVimprjRootParams'].projectName)
               call <SID>AddNewProjectToCurFile(l:sProjFileKey, l:sCurProjName, l:iFileNum)
            endif
         endfor

      endif 


      " теперь запускаем ctags для каждого непроиндексированного проекта, 
      " в который входит файл
      for l:sCurProj in g:vimprj#dFiles[ l:iFileNum ].projects
         if (!s:dProjFilesParsed[ l:sCurProj.file ]["projects"][ l:sCurProj.name ].boolIndexed)
            " генерим теги
            call <SID>UpdateTagsForProject(l:sCurProj.file, l:sCurProj.name, "", a:dParams['dVimprjRootParams'])
         endif

      endfor



   endif " if l:sProjFileKey != ""

   "call <SID>SetTagsAndPath(l:iFileNum, l:sVimprjKey)

   call <SID>_AddToDebugLog(s:DEB_LEVEL__PARSE, 'function end: __OnFileOpen__', {})
endfunction

" добавляет новый vimprj root, заполняет его текущими параметрами
function! g:vimprj#dHooks['OnAddNewVimprjRoot']['indexer'](dParams)

   let l:sVimprjKey = a:dParams['sVimprjKey']

   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer'] = {}
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["useSedWhenAppend"]                 = g:indexer_useSedWhenAppend
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["indexerListFilename"]              = g:indexer_indexerListFilename
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["projectsSettingsFilename"]         = g:indexer_projectsSettingsFilename
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["projectName"]                      = g:indexer_projectName
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["enableWhenProjectDirFound"]        = g:indexer_enableWhenProjectDirFound
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["ctagsCommandLineOptions"]          = g:indexer_ctagsCommandLineOptions
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["ctagsJustAppendTagsAtFileSave"]    = g:indexer_ctagsJustAppendTagsAtFileSave
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["useDirsInsteadOfFiles"]            = g:indexer_ctagsDontSpecifyFilesIfPossible
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["backgroundDisabled"]               = g:indexer_backgroundDisabled
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["handlePath"]                       = g:indexer_handlePath
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["ctagsWriteFilelist"]               = g:indexer_ctagsWriteFilelist
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["mode"]                             = ""
   let g:vimprj#dRoots[ l:sVimprjKey ]['indexer']["getAllSubdirsFromIndexerListFile"] = g:indexer_getAllSubdirsFromIndexerListFile

endfunction


function! g:vimprj#dHooks['SetDefaultOptions']['indexer'](dParams)
   let g:indexer_useSedWhenAppend                 = s:def_useSedWhenAppend
   let g:indexer_projectsSettingsFilename         = s:def_projectsSettingsFilename
   let g:indexer_projectName                      = s:def_projectName
   let g:indexer_enableWhenProjectDirFound        = s:def_enableWhenProjectDirFound
   let g:indexer_ctagsCommandLineOptions          = s:def_ctagsCommandLineOptions
   let g:indexer_ctagsJustAppendTagsAtFileSave    = s:def_ctagsJustAppendTagsAtFileSave
   let g:indexer_ctagsDontSpecifyFilesIfPossible  = s:def_ctagsDontSpecifyFilesIfPossible
   let g:indexer_backgroundDisabled               = s:def_backgroundDisabled
   let g:indexer_handlePath                       = s:def_handlePath
   let g:indexer_getAllSubdirsFromIndexerListFile = s:def_getAllSubdirsFromIndexerListFile
   let g:indexer_ctagsWriteFilelist               = s:def_ctagsWriteFilelist

   if !empty(a:dParams['sVimprjDirName'])
      let $INDEXER_PROJECT_ROOT = simplify(a:dParams['sVimprjDirName'].'/..')
   endif

   let &tags = s:sTagsDefault
   let &path = s:sPathDefault

endfunction

function! g:vimprj#dHooks['OnBufSave']['indexer'](dParams)
   call <SID>_AddToDebugLog(s:DEB_LEVEL__PARSE, 'function start: __OnBufSave__', {'filename' : expand('<afile>')})

   let l:iFileNum = a:dParams['iFileNum']

   call <SID>UpdateTagsForFile(l:iFileNum)

   "call <SID>UpdateTagsForFile(
   "\     '<afile>',
   "\     g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer'].ctagsJustAppendTagsAtFileSave,
   "\     g:vimprj#iCurFileNum
   "\  )
   call <SID>_AddToDebugLog(s:DEB_LEVEL__PARSE, 'function end: __OnBufSave__', {})
endfunction






" ************************************************************************************************
"                                   ASYNC COMMAND FUNCTIONS
" ************************************************************************************************

" ------------------ next 2 functions is directly from asynccommand.vim ---------------------

" Basic background task running is different on each platform
if has("win32") || has("win64")
   " Works in Windows (Win7 x64)
   function! <SID>IndexerAsync_Impl(tool_cmd, vim_cmd)
      let l:cmd = a:tool_cmd

      if !empty(a:vim_cmd)
         let l:cmd .= " & ".a:vim_cmd
      endif

      silent exec "!start /MIN cmd /c \"".l:cmd."\""
   endfunction
else
   " Works in linux (Ubuntu 10.04)
   function! <SID>IndexerAsync_Impl(tool_cmd, vim_cmd)

      let l:cmd = a:tool_cmd

      if !empty(a:vim_cmd)
         let l:cmd .= " ; ".a:vim_cmd
      endif

      silent exec "! (".l:cmd.") &"
   endfunction
endif

function! <SID>IndexerAsyncCommand(command, vim_func)

   " async works if only v:servername is not empty!
   " otherwise we should wait for output here.

   if <SID>_IsBackgroundEnabled()

      " String together and execute.
      let temp_file = tempname()

      " Grab output and error in case there's something we should see
      let tool_cmd = a:command . printf(&shellredir, temp_file)

      let vim_cmd = ""
      if !empty(a:vim_func)
         "let vim_cmd = "vim --servername ".v:servername." --remote-expr \"" . a:vim_func . "('" . temp_file . "')\" "
      endif

      call <SID>IndexerAsync_Impl(tool_cmd, vim_cmd)
   else
      " v:servername is empty! (or g:indexer_backgroundDisabled is not empty)
      " so, no async is present.
      let l:sCmdOutput = system(a:command)
      call <SID>Indexer_ParseCommandOutput(l:sCmdOutput)

   endif

endfunction

" ---------------------- my async level ----------------------

function! <SID>AddNewAsyncTask(dParams)
   "call add(s:lAsyncTasks, a:dParams)
   let s:dAsyncTasks[ s:iAsyncTaskLast ] = a:dParams
   let s:iAsyncTaskLast += 1
   if !s:boolAsyncCommandInProgress
      call <SID>_ExecNextAsyncTask()
   endif

endfunction

function! <SID>_ExecNextAsyncTask()

   "echo s:dAsyncTasks
   if !s:boolAsyncCommandInProgress && s:iAsyncTaskNext < s:iAsyncTaskLast
      let s:boolAsyncCommandInProgress = 1
      let l:dParams = s:dAsyncTasks[ s:iAsyncTaskNext ]
      " s:dAsyncTasks unlets in <SID>Indexer_ParseCommandOutput()
      let s:iAsyncTaskCur  += 1
      let s:iAsyncTaskNext += 1

      call <SID>_AddToDebugLog(s:DEB_LEVEL__ASYNC, 'asyncCmd', l:dParams)

      if l:dParams["mode"] == "AsyncModeCtags"

         let s:sLastCtagsCmd = <SID>GetCtagsCommand(l:dParams["data"])
         let s:sLastCtagsOutput = "** no output yet **"
         call <SID>IndexerAsyncCommand(s:sLastCtagsCmd, "Indexer_OnAsyncCommandComplete")

      elseif l:dParams["mode"] == "AsyncModeSed"

         call <SID>IndexerAsyncCommand(l:dParams["data"]["sSedCmd"], "Indexer_OnAsyncCommandComplete")

      elseif l:dParams["mode"] == "AsyncModeDelete"

         if filereadable(l:dParams["data"]["filename"])
            call delete(l:dParams["data"]["filename"])
         endif

         " we should make dummy async call
         "call <SID>IndexerAsyncCommand(s:dCtagsInfo['executable']." --version", "Indexer_OnAsyncCommandComplete")
         call <SID>_AsyncDummyComplete()

      elseif l:dParams["mode"] == "AsyncModeRename"

         if filereadable(l:dParams["data"]["filename_old"])
            if filereadable(l:dParams["data"]["filename_new"])
               call delete(l:dParams["data"]["filename_new"])
            endif
            call rename(l:dParams["data"]["filename_old"], l:dParams["data"]["filename_new"])
         endif

         " we should make dummy async call
         "call <SID>IndexerAsyncCommand(s:dCtagsInfo['executable']." --version", "Indexer_OnAsyncCommandComplete")
         call <SID>_AsyncDummyComplete()
      endif
   endif

endfunction

function! <SID>_AsyncDummyComplete()
   call <SID>Indexer_ParseCommandOutput("dummy")
endfunction

function! Indexer_OnAsyncCommandComplete(temp_file_name)


   let l:lCmdOutput = readfile(a:temp_file_name)
   let l:sCmdOutput = join(l:lCmdOutput, "\n")

   call <SID>Indexer_ParseCommandOutput(l:sCmdOutput)

   "exec "split " . a:temp_file_name
   "wincmd w
   "redraw

endfunction


" ************************************************************************************************
"                                      DEBUG FUNCTIONS
" ************************************************************************************************

function! <SID>_AddToDebugLog(iLevel, sType, dData)

   if s:indexer_debugLogLevel >= a:iLevel
      let l:dLogItem = {'level' : a:iLevel, 'type' : a:sType, 'data' : a:dData}
      call add(s:lDebug, l:dLogItem)

      " write log item to file, if file specified
      if !empty(s:indexer_debugLogFilename)
         exec ':redir >> '.s:indexer_debugLogFilename.' | silent call <SID>_EchoLogItem(l:dLogItem) | redir END'
      endif
   endif

endfunction

function! <SID>_EchoLogItem(dLogItem)
   if exists("*strftime")
      echo '* '.a:dLogItem["level"].' -------------------- '.strftime("%c").' --------------------*'
   else
      echo '* '.a:dLogItem["level"].' -------------------- *'
   endif
   echo 'type: '.a:dLogItem["type"].';     data:'
   echo a:dLogItem["data"]
endfunction

function! <SID>IndexerDebugLog()
   if !empty(s:indexer_debugLogLevel)

      echo " Log level: ".s:indexer_debugLogLevel
      echo ""

      for l:dLogItem in s:lDebug
         call <SID>_EchoLogItem(l:dLogItem)
      endfor

   else
      echo 'Debug log is disabled. To enable, please define g:indexer_debugLogLevel > 0.'
   endif
endfunction

function! <SID>IndexerDebugInfo()
   echo '* Ctags executable: '.s:dCtagsInfo['executable']
   echo '* Ctags versionOutput: '.s:dCtagsInfo['versionOutput']
   echo '* Ctags boolCtagsExists: '.s:dCtagsInfo['boolCtagsExists']
   echo '* Ctags boolPatched: '.s:dCtagsInfo['boolPatched']
   echo '* Ctags versionFirstLine: '.s:dCtagsInfo['versionFirstLine']
   echo '* Ctags last command: "'.s:sLastCtagsCmd.'"'
   echo '* Ctags last output: "'.s:sLastCtagsOutput.'"'
endfunction


function! <SID>IndexerDebugSave()

   if empty(s:indexer_debugLogLevel)
      echomsg "Warning: log is disabled. To enable, please define g:indexer_debugLogLevel > 0."
   endif

   let l:sFilename = input("Enter filename to save debug info: ")
   if !empty(l:sFilename)

      if filereadable(l:sFilename)
         call delete(l:sFilename)
      endif

      if writefile(["VIM Indexer debug snapshot", ""], l:sFilename) != 0
         call confirm("failed to write file: ".l:sFilename)
      else

         exec ':redir >> '.l:sFilename
         silent echo ":version"
         silent version
         silent echo ""
         silent echo ":IndexerInfo"
         silent call <SID>IndexerInfo()
         silent echo ""
         silent echo ":IndexerDebugInfo"
         silent call <SID>IndexerDebugInfo()
         silent echo ""
         silent echo ":IndexerDebugLog"
         silent call <SID>IndexerDebugLog()
         redir END
         echomsg "debug snapshot saved successfully."
      endif

   endif
endfunction


" ************************************************************************************************
"                                      ADDITIONAL FUNCTIONS
" ************************************************************************************************

function! <SID>_GetPathLastItem(sPath)
   return substitute(a:sPath, '\v^.*[\\/]([^\\/]+)[\\/]{0,1}$', '\1', '')
endfunction

function! <SID>_UseDirsInsteadOfFiles(dVimprjRoot)
   if (a:dVimprjRoot.mode == 'IndexerFile')
      if (a:dVimprjRoot.useDirsInsteadOfFiles == 0)
         return 0
      else
         return 1
      endif
   else
      if (a:dVimprjRoot.useDirsInsteadOfFiles == 1)
         return 1
      else
         return 0
      endif
   endif
endfunction

function! <SID>_IsBackgroundEnabled()
   "return (!empty(v:servername) && empty(g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer'].backgroundDisabled))
   return 1
endfunction

function! <SID>_GetBackgroundComment()
   let l:sComment = ""

   if empty(v:servername)
      if !empty(l:sComment)
         let l:sComment .= ", "
      endif
      let l:sComment .= "because of v:servername is empty (:help servername)"
   endif

   if !empty(g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer'].backgroundDisabled)
      if !empty(l:sComment)
         let l:sComment .= ", "
      endif
      let l:sComment .= "because of g:indexer_backgroundDisabled is not empty"
   endif

   if !empty(l:sComment)
      let l:sComment = "(".l:sComment.")"
   endif

   return l:sComment
endfunction

function! <SID>Indexer_ParseCommandOutput(sOutput)
   let l:dParams = s:dAsyncTasks[ s:iAsyncTaskCur ]
   unlet s:dAsyncTasks[ s:iAsyncTaskCur ]

   call <SID>_AddToDebugLog(s:DEB_LEVEL__ASYNC, 'asyncCmdResponse', {'mode' : l:dParams['mode'], 'output' : a:sOutput})

   if l:dParams['mode'] == 'AsyncModeCtags'
      " we need to save last ctags output, for debug
      let s:sLastCtagsOutput = a:sOutput

      " ctags output should be empty.
      " if it is not, then we should show warning
      if len(matchlist(s:sLastCtagsOutput, "[a-zA-Z0-9_а-яА-Я.,-=!\\/]")) > 0
         if empty(s:indexer_disableCtagsWarning)
            let l:iMaxCmdLenToShow = 200
            if strlen(s:sLastCtagsCmd) > l:iMaxCmdLenToShow
               let l:sCtagsCmd = strpart(s:sLastCtagsCmd, 0, l:iMaxCmdLenToShow)."....(cutted, to see full command, type :IndexerDebugInfo)"
            else
               let l:sCtagsCmd = s:sLastCtagsCmd
            endif
            call confirm ("Indexer warning: ctags output was not empty: \n\"".s:sLastCtagsOutput."\"\n\nCtags command was:\n\"".l:sCtagsCmd."\"\n\nIf you want to disable this warning, please set option g:indexer_disableCtagsWarning=1")
         endif
      endif
   endif

   let s:boolAsyncCommandInProgress = 0
   call <SID>_ExecNextAsyncTask()

endfunction

function! <SID>DeleteFile(filename)
   call <SID>AddNewAsyncTask({
            \     'mode' : 'AsyncModeDelete',
            \     'data' : { 
            \        'filename' : a:filename 
            \     } 
            \  })
endfunction

function! <SID>RenameFile(filename_old, filename_new)
   call <SID>AddNewAsyncTask({
            \     'mode' : 'AsyncModeRename', 
            \     'data' : { 
            \        'filename_old' : a:filename_old,
            \        'filename_new' : a:filename_new 
            \     } 
            \  })
endfunction

function! <SID>AddNewProjectToCurFile(sProjFileKey, sProjName, iFileNum)
   call add(g:vimprj#dFiles[ a:iFileNum ].projects, {"file" : a:sProjFileKey, "name" : a:sProjName})
endfunction

function! <SID>GetKeyFromPath(sPath)
   let l:sKey = substitute(a:sPath, '[^a-zA-Z0-9_]', '_', 'g')

   if has('win32') || has('win64')
      let l:sKey = tolower(l:sKey)
   endif

   return l:sKey
endfunction

function! <SID>IndexerFilesList()
   if (<SID>_UseDirsInsteadOfFiles(g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer']))
      echo "option g:indexer_ctagsDontSpecifyFilesIfPossible is ON. So, Indexer knows nothing about files."
   else
      if len(g:vimprj#dFiles[ g:vimprj#iCurFileNum ]["projects"]) > 0
         echo "* Files indexed: ".join(
                     \  s:dProjFilesParsed 
                     \      [ g:vimprj#dFiles[ g:vimprj#iCurFileNum ]["projects"][0]["file"] ]
                     \      [ "projects" ]
                     \      [ g:vimprj#dFiles[ g:vimprj#iCurFileNum ]["projects"][0]["name"] ]
                     \      ["files"] 
                     \  )
      else
         echo "There's no projects indexed."
      endif
   endif
endfunction

" concatenates two lists preventing duplicates
function! <SID>ConcatLists(lExistingList, lAddingList)
   let l:lResList = a:lExistingList
   for l:sItem in a:lAddingList
      if (index(l:lResList, l:sItem) == -1)
         call add(l:lResList, l:sItem)
      endif
   endfor
   return l:lResList
endfunction

" <SID>ParsePath(sPath)
"   changing '\' to '/' or vice versa depending on OS (MS Windows or not) also calls simplify()
function! <SID>ParsePath(sPath)
   if (has('win32') || has('win64'))
      let l:sPath = substitute(a:sPath, '/', '\', 'g')
   else
      let l:sPath = substitute(a:sPath, '\', '/', 'g')
   endif
   let l:sPath = simplify(l:sPath)

   " removing last "/" or "\"
   let l:sLastSymb = strpart(l:sPath, (strlen(l:sPath) - 1), 1)
   if (l:sLastSymb == '/' || l:sLastSymb == '\')
      let l:sPath = strpart(l:sPath, 0, (strlen(l:sPath) - 1))
   endif
   return l:sPath
endfunction

" <SID>Trim(sString)
" trims spaces from begin and end of string
function! <SID>Trim(sString)
   return substitute(substitute(a:sString, '^\s\+', '', ''), '\s\+$', '', '')
endfunction

" <SID>IsAbsolutePath(path) <<<
"   this function from project.vim is written by Aric Blumer.
"   Returns true if filename has an absolute path.
function! <SID>IsAbsolutePath(path)
   if a:path =~ '^ftp:' || a:path =~ '^rcp:' || a:path =~ '^scp:' || a:path =~ '^http:'
      return 2
   endif
   let path=expand(a:path) " Expand any environment variables that might be in the path
   if path[0] == '/' || path[0] == '~' || path[0] == '\\' || path[1] == ':'
      return 1
   endif
   return 0
endfunction " >>>

function! <SID>BufName(mValue)
   let l:sFilename = bufname(a:mValue)
   if !empty(l:sFilename) && !<SID>IsAbsolutePath(l:sFilename)
      let l:sFilename = getcwd().'/'.l:sFilename
   endif

   return l:sFilename
endfunction

" returns whether or not file exists in list
function! <SID>IsFileExistsInList(aList, sFilename)
   let l:sFilename = <SID>ParsePath(a:sFilename)
   if (index(a:aList, l:sFilename, 0, 1)) >= 0
      return 1
   endif
   return 0
endfunction



function! <SID>IndexerInfo()

   let l:sProjects = ""
   let l:sPathsRoot = ""
   let l:sPathsForCtags = ""
   let l:iFilesCnt = 0
   let l:iFilesNotFoundCnt = 0

   for l:lProjects in g:vimprj#dFiles[ g:vimprj#iCurFileNum ]["projects"]
      let l:dCurProject = s:dProjFilesParsed[ l:lProjects.file ]["projects"][ l:lProjects.name ]

      if !empty(l:sProjects)
         let l:sProjects .= ", "
      endif
      let l:sProjects .= l:lProjects.name

      if !empty(l:sPathsRoot)
         let l:sPathsRoot .= ", "
      endif
      let l:sPathsRoot .= join(l:dCurProject.pathsRoot, ', ')

      if !empty(l:sPathsForCtags)
          let l:sPathsForCtags .= ", "
      endif
      let l:sPathsForCtags .= join(l:dCurProject.pathsForCtags, ', ')
      let l:iFilesCnt += len(l:dCurProject.files)
      let l:iFilesNotFoundCnt += len(l:dCurProject.not_exist)

   endfor

   call <SID>Indexer_DetectCtags()

   let l:iVersionStrlen = strlen(g:iIndexerVersion)
   echo '* Indexer version: '.strpart(g:iIndexerVersion, 0, l:iVersionStrlen - 2).'.'.strpart(g:iIndexerVersion, l:iVersionStrlen - 2)

   if empty(s:dCtagsInfo['boolCtagsExists'])
      echo '* Error: Ctags NOT FOUND. You need to install Exuberant Ctags to make Indexer work. The better way is to install patched ctags: http://dfrank.ru/ctags581/en.html'
   else
      echo '* Ctags version: '.s:dCtagsInfo['versionFirstLine']
      
      if (g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer'].mode == '')
         echo '* Filelist: not found'
      elseif (g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer'].mode == 'IndexerFile')
         echo '* Filelist: indexer file: '.g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer'].indexerListFilename
      elseif (g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer'].mode == 'ProjectFile')
         echo '* Filelist: project file: '.g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer'].projectsSettingsFilename
      else
         echo '* Filelist: Unknown'
      endif
      if (<SID>_UseDirsInsteadOfFiles(g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer']))
         echo '* Index-mode: DIRS. (option g:indexer_ctagsDontSpecifyFilesIfPossible is ON)'
      else
         echo '* Index-mode: FILES. (option g:indexer_ctagsDontSpecifyFilesIfPossible is OFF)'
      endif
      echo '* At file save: '.
               \ (g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer'].ctagsJustAppendTagsAtFileSave 
               \     ? (g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer'].useSedWhenAppend 
               \           ? 'remove tags for saved file by SED, and ' 
               \           : ''
               \       ).'just append tags' 
               \     : 'rebuild tags for whole project'
               \ )
      if <SID>_IsBackgroundEnabled()
         echo '* Background tags generation: YES'
      else
         echo '* Background tags generation: NO. '.<SID>_GetBackgroundComment()
      endif
      echo '* Projects indexed: '.l:sProjects
      if (!<SID>_UseDirsInsteadOfFiles(g:vimprj#dRoots[ g:vimprj#sCurVimprjKey ]['indexer']))
         echo "* Files indexed: there's ".l:iFilesCnt.' files. Type :IndexerFiles for list.'
         " Type :IndexerFiles to list'
         echo "* Files not found: there's ".l:iFilesNotFoundCnt.' non-existing files. ' 
         ".join(s:dParseGlobal.not_exist, ', ')
      endif

      echo "* Root paths: ".l:sPathsRoot
      echo "* Paths for ctags: ".l:sPathsForCtags

      echo '* Paths (with all subfolders): '.&path
      echo '* Tags file: '.&tags

      "TODO
      "echo '* Project root: '
               "\  .($INDEXER_PROJECT_ROOT != '' ? $INDEXER_PROJECT_ROOT : 'not found')
               "\  .'  (Project root is a directory which contains "'
               "\  .s:indexer_dirNameForSearch.'" directory)'
   endif
endfunction




" ************************************************************************************************
"                                   CTAGS UNIVERSAL FUNCTIONS
" ************************************************************************************************

" generates command to call ctags apparently params.
" params:
"   dParams {
"      append,          // 1 or 0
"      recursive,       // 1 or 0
"      sTagsFile,       // ".." - filename to save tags.
"                                 Will be passed to ctags with -f key.
"      sFiles,          // ".." - just string with filenames to be indexed.
"                                 Will be passed to ctags literally.
"      sFilelistFile,   // ".." - file with list of files to be indexed. 
"                                 Will be passed to ctags with -L key.
"      dIndexerParams,  // g:vimprj#dRoots[ l:sVimprjKey ]['indexer']
"   }
function! <SID>GetCtagsCommand(dParams)
   let l:sAppendCode = ''
   let l:sRecurseCode = ''
   let l:sFilelistFileCode = ''

   if (a:dParams.append)
      let l:sAppendCode = '-a'
   endif

   if (a:dParams.recursive)
      let l:sRecurseCode = '-R'
   endif


   if has_key(a:dParams, 'sFilelistFile') && !empty(a:dParams.sFilelistFile)
      let l:sFilelistFileCode = '-L "'.a:dParams.sFilelistFile.'"'
   endif

   " when using append without Sed we SHOULD use sort, because of if there's no sort, then
   " symbols will be doubled.
   "
   " when using append with Sed on Windows (cygwin) we SHOULD NOT use sort, because of if there's sort, then
   " tags file becomes damaged because of Sed's output is always with UNIX
   " line-ends. Ctags at Windows fails with this file.
   "
   if (a:dParams['dIndexerParams'].ctagsJustAppendTagsAtFileSave && a:dParams['dIndexerParams'].useSedWhenAppend && (has('win32') || has('win64')))
      let l:sSortCode = '--sort=no'
   else
      let l:sSortCode = '--sort=yes'
   endif

   let l:sTagsFile = '"'.a:dParams.sTagsFile.'"'
   let l:sCmd = s:dCtagsInfo['executable']
            \  .' -f '.l:sTagsFile.' '
            \  .l:sRecurseCode.' '
            \  .l:sAppendCode.' '
            \  .l:sSortCode.' '
            \  .l:sFilelistFileCode.' '
            \  .a:dParams['dIndexerParams'].ctagsCommandLineOptions.' '
            \  .a:dParams.sFiles

   return l:sCmd
endfunction

" executes ctags called with specified params.
" params look in comments to <SID>GetCtagsCommand()
function! <SID>ExecCtags(dParams)
   let l:dAsyncParams = {'mode' : 'AsyncModeCtags' , 'data' : a:dParams}
   call <SID>AddNewAsyncTask(l:dAsyncParams)
endfunction


" builds list of files (or dirs) and executes Ctags.
" If list is too long (if command is more that s:indexer_maxOSCommandLen)
" then executes ctags several times.
" params:
"   dParams {
"      lFilelist, // [..]
"      sTagsFile, // ".."
"      recursive  // 1 or 0
"   }
function! <SID>ExecCtagsForListOfFiles(dParams)

   if len(a:dParams.lFilelist) > 2 && a:dParams.dIndexerParams['ctagsWriteFilelist']
      " write filelist and pass it to ctags with -L key
      let l:sFilelistFilename = a:dParams.sTagsFile."_files"

      " TODO: check if writefile succeed, and if not, then run 'usual'
      " scenario to build tags
      call writefile(a:dParams.lFilelist, l:sFilelistFilename)

      call <SID>ExecCtags({
               \     'append'         : 0,
               \     'recursive'      : a:dParams.recursive,
               \     'sTagsFile'      : a:dParams.sTagsFile,
               \     'sFilelistFile'  : l:sFilelistFilename,
               \     'sFiles'         : '',
               \     'dIndexerParams' : a:dParams.dIndexerParams
               \  })
      
   else
      " specify filenames (or dirnames) directly in command line to ctags

      " we need to know length of command to call ctags (without any files)
      let l:sCmd = <SID>GetCtagsCommand({
               \     'append'         : 1,
               \     'recursive'      : a:dParams.recursive,
               \     'sTagsFile'      : a:dParams.sTagsFile,
               \     'sFiles'         : "",
               \     'dIndexerParams' : a:dParams.dIndexerParams
               \  })
      let l:iCmdLen = strlen(l:sCmd)


      " now enumerating file
      let l:sFiles = ''
      for l:sCurFile in a:dParams.lFilelist

         let l:sCurFile = <SID>ParsePath(l:sCurFile)
         " if command with next file will be too long, then executing command
         " BEFORE than appending next file to list
         if ((strlen(l:sFiles) + strlen(l:sCurFile) + l:iCmdLen) > s:indexer_maxOSCommandLen)
            call <SID>ExecCtags({
                     \     'append': 1,
                     \     'recursive'      : a:dParams.recursive,
                     \     'sTagsFile'      : a:dParams.sTagsFile,
                     \     'sFiles'         : l:sFiles,
                     \     'dIndexerParams' : a:dParams.dIndexerParams
                     \  })
            let l:sFiles = ''
         endif

         let l:sFiles = l:sFiles.' "'.l:sCurFile.'"'
      endfor

      if (l:sFiles != '')
         call <SID>ExecCtags({
                  \     'append': 1,
                  \     'recursive'      : a:dParams.recursive,
                  \     'sTagsFile'      : a:dParams.sTagsFile,
                  \     'sFiles'         : l:sFiles,
                  \     'dIndexerParams' : a:dParams.dIndexerParams
                  \  })
      endif

   endif

endfunction



function! <SID>ExecSed(dParams)
   " linux: all should work
   " windows: cygwin works, non-cygwin needs \\ instead of \\\\
   let l:sFilenameToDeleteTagsWith = a:dParams.sFilenameToDeleteTagsWith

   let l:sFilenameToDeleteTagsWith = substitute(l:sFilenameToDeleteTagsWith, "\\\\", "\\\\\\\\\\\\\\\\", "g")
   let l:sFilenameToDeleteTagsWith = substitute(l:sFilenameToDeleteTagsWith, "\\.", "\\\\\\\\.", "g")
   let l:sFilenameToDeleteTagsWith = substitute(l:sFilenameToDeleteTagsWith, "\\/", "\\\\\\\\/", "g")

   "let l:sFilenameToDeleteTagsWith = substitute(l:sFilenameToDeleteTagsWith, "\\\\", "\\\\\\\\", "g")
   "let l:sFilenameToDeleteTagsWith = substitute(l:sFilenameToDeleteTagsWith, "\\.", "\\\\.", "g")
   "let l:sFilenameToDeleteTagsWith = substitute(l:sFilenameToDeleteTagsWith, "\\/", "\\\\/", "g")

   "let l:sCmd = "sed -e \"/".l:sFilenameToDeleteTagsWith."/d\" \"".a:dParams.sTagsFile."\" > \"".a:dParams.sTagsFile."_tmp\""
   "let l:sCmd = "sed -e \"/iqqqqqqqqqq/d\" < \"".a:dParams.sTagsFile."\" > \"".a:dParams.sTagsFile."_tmp\""
   "let df = input(l:sCmd)
   "let l:sCmd = "sed -e \"/^.*\\s".l:sFilenameToDeleteTagsWith."\\s.*$/d\" -i \"".a:dParams.sTagsFile."\""

   let l:sCmd = "sed -e \"/".l:sFilenameToDeleteTagsWith."/d\" -i \"".a:dParams.sTagsFile."\""

   let l:dAsyncParams = {'mode' : 'AsyncModeSed' , 'data' : {'sSedCmd' : l:sCmd}}
   call <SID>AddNewAsyncTask(l:dAsyncParams)

   "call <SID>RenameFile(a:dParams.sTagsFile."_tmp", a:dParams.sTagsFile)

   "let l:resp = system(l:sCmd)


   "if exists("*AsyncCommand")
      "call AsyncCommand(l:sCmd, "")
   "else
      "let l:resp = system(l:sCmd)
   "endif

endfunction

" ************************************************************************************************
"                                   CTAGS SPECIAL FUNCTIONS
" ************************************************************************************************

function! <SID>IndexerGetCtagsName()
   " Location of the exuberant ctags tool_cmd
   " (token from taglist plugin)

   let l:sCtagsName = ''
   if executable('exuberant-ctags')
      " On Debian Linux, exuberant ctags is installed
      " as exuberant-ctags
      let l:sCtagsName = 'exuberant-ctags'
   elseif executable('exctags')
      " On Free-BSD, exuberant ctags is installed as exctags
      let l:sCtagsName = 'exctags'
   elseif executable('ctags')
      let l:sCtagsName = 'ctags'
   elseif executable('ctags.exe')
      let l:sCtagsName = 'ctags.exe'
   elseif executable('tags')
      let l:sCtagsName = 'tags'
   endif

   return l:sCtagsName

endfunction

function! <SID>IndexerGetCtagsVersion()

   let l:dCtagsInfo = {'executable' : '', 'versionOutput' : '', 'boolCtagsExists' : 0, 'boolPatched' : 0, 'versionFirstLine' : ''}

   let l:dCtagsInfo['executable'] = <SID>IndexerGetCtagsName()

   if !empty(l:dCtagsInfo['executable'])
      let l:dCtagsInfo['boolCtagsExists'] = 1

      let l:dCtagsInfo['versionOutput'] = system(l:dCtagsInfo['executable']." --version")

      if len(matchlist(l:dCtagsInfo['versionOutput'], "\\vExuberant")) > 0

         let l:dCtagsInfo['versionFirstLine'] = substitute(l:dCtagsInfo['versionOutput'], "\\v^([^\r\n]*).*$", "\\1", "g")

         if len(matchlist(l:dCtagsInfo['versionOutput'], "\\vdimon\\.frank\\@gmail\\.com")) > 0
            let l:dCtagsInfo['boolPatched'] = 1
         endif

      endif
   else
      " if executable is empty, let's set it to "ctags", anyway.
      let l:dCtagsInfo['executable'] = 'ctags'
   endif

   return l:dCtagsInfo

endfunction

function! <SID>Indexer_DetectCtags()
   let s:dCtagsInfo = <SID>IndexerGetCtagsVersion()
endfunction

" update tags for one project.
" 
" params:
"     sProjFileKey - key for s:dProjFilesParsed
"     sProjName - project name in this projects file
"     sSavedFile - CAN BE EMPTY.
"                  if empty, then updating ALL tags for given project.
"                  otherwise, updating tags for just this file with Append.
function! <SID>UpdateTagsForProject(sProjFileKey, sProjName, sSavedFile, dIndexerParams)

   call <SID>_AddToDebugLog(s:DEB_LEVEL__PARSE, 'function start: __UpdateTagsForProject__', {'sProjFileKey' : a:sProjFileKey, 'sProjName' : a:sProjName, 'sSavedFile' : a:sSavedFile})

   if empty(s:dCtagsInfo['boolCtagsExists'])
      call <SID>Indexer_DetectCtags()
   endif
   
   if !empty(s:dCtagsInfo['boolCtagsExists'])
      let l:sTagsFile = s:dProjFilesParsed[ a:sProjFileKey ]["projects"][ a:sProjName ].tagsFilename
      let l:dCurProject = s:dProjFilesParsed[a:sProjFileKey]["projects"][ a:sProjName ]

      if (!empty(a:sSavedFile) && filereadable(l:sTagsFile))
         " just appending tags from just saved file. (from one file!)
         if (a:dIndexerParams['useSedWhenAppend'])
            call <SID>ExecSed({'sTagsFile': l:sTagsFile, 'sFilenameToDeleteTagsWith': a:sSavedFile})
         endif
         call <SID>ExecCtags({
                  \     'append': 1,
                  \     'recursive': 0,
                  \     'sTagsFile': l:sTagsFile,
                  \     'sFiles': a:sSavedFile,
                  \     'dIndexerParams' : a:dIndexerParams
                  \  })

      else
         " need to rebuild all tags.

         " deleting old tagsfile
         "if (filereadable(l:sTagsFile))
            "call delete(l:sTagsFile)
         "endif
         "let l:dAsyncParams = {'mode' : 'AsyncModeDelete' , 'data' : { 'filename' : l:sTagsFile } }

         call <SID>DeleteFile(l:sTagsFile."_tmp")

         " generating tags for files
         call <SID>ExecCtagsForListOfFiles({
                  \     'lFilelist'      : l:dCurProject.files,
                  \     'sTagsFile'      : l:sTagsFile."_tmp",
                  \     'recursive'      : 0,
                  \     'dIndexerParams' : a:dIndexerParams
                  \  })

         " generating tags for directories
         call <SID>ExecCtagsForListOfFiles({
                  \     'lFilelist'      : l:dCurProject.pathsForCtags,
                  \     'sTagsFile'      : l:sTagsFile."_tmp",
                  \     'recursive'      : 1,
                  \     'dIndexerParams' : a:dIndexerParams
                  \  })

         call <SID>RenameFile(l:sTagsFile."_tmp", l:sTagsFile)

      endif




      let s:dProjFilesParsed[ a:sProjFileKey ]["projects"][ a:sProjName ].boolIndexed = 1
   endif

   call <SID>_AddToDebugLog(s:DEB_LEVEL__PARSE, 'function end: __UpdateTagsForProject__', {'sProjName' : a:sProjName, 'sSavedFile' : a:sSavedFile})
endfunction

" re-read projects from given file, 
" update all tags for every project that is already indexed
"
function! <SID>UpdateTagsForEveryNeededProjectFromFile(sProjFileKey)

   call <SID>ParseProjectSettingsFile(a:sProjFileKey)
   let l:sVimprjKey = s:dProjFilesParsed[ a:sProjFileKey ]["sVimprjKey"]

   " list of projects we should index
   let l:lProjects = []

   " searching for all currently indexed projects from given projects file
   " (we should re-index them all)
   for l:iFileNum in keys(g:vimprj#dFiles)
      for l:dProjectFile in g:vimprj#dFiles[ l:iFileNum ]["projects"]
         if (l:dProjectFile["file"] == a:sProjFileKey && index(l:lProjects, l:dProjectFile["name"]) == -1)
            call add(l:lProjects, l:dProjectFile["name"])
         endif
      endfor
   endfor

   for l:sProject in l:lProjects
      call <SID>UpdateTagsForProject(a:sProjFileKey, l:sProject, "", g:vimprj#dRoots[ l:sVimprjKey ]['indexer'])
   endfor

endfunction








"                         FUNCTIONS TO PARSE PROJECT FILE OR INDEXER FILE
" ************************************************************************************************

" возвращает dictionary:
" dResult[<название_проекта_1>][files]
"                              [paths]
"                              [not_exist]
"                              [pathsForCtags]
"                              [pathsRoot]
" dResult[<название_проекта_2>][files]
"                              [paths]
"                              [not_exist]
"                              [pathsForCtags]
"                              [pathsRoot]
" ...
"
" параметры:                             
" param aLines все строки файла (т.е. файл надо сначала прочитать)
" param indexerFile имя файла (используется только для того, чтобы распарсить
" названия проектов типа [%dir_name(..)%])
" param projectName название проекта, который нужно прочитать.
"                   если пустой, то будут прочитаны
"                   все проекты из файла
" param dExistsResult уже существующий dictionary, к которому будут
" добавлены полученные результаты
"
function! <SID>GetDirsAndFilesFromIndexerList(aLines, indexerFile, dExistsResult, dIndexerParams)
   let l:aLines = a:aLines
   let l:dResult = a:dExistsResult
   let l:boolInNeededProject = (a:dIndexerParams['projectName'] == '' ? 1 : 0)
   let l:boolInProjectsParentSection = 0
   let l:sProjectsParentFilter = ''

   let l:sCurProjName = ''

   for l:sLine in l:aLines

      " if line is not empty
      if l:sLine !~ '^\s*$' && l:sLine !~ '^\s*\#.*$'

         " look for project name [PrjName]
         let l:myMatch = matchlist(l:sLine, '^\s*\[\([^\]]\+\)\]')

         if (len(l:myMatch) > 0)
            " remember what is in []
            let l:sProjName = l:myMatch[1]

            " check for PROJECTS_PARENT section

            if (strpart(l:sProjName, 0, 15) == 'PROJECTS_PARENT')
               " this is projects parent section
               let l:sProjectsParentFilter = ''
               let l:filterMatch = matchlist(l:sProjName, 'filter="\([^"]\+\)"')
               if (len(l:filterMatch) > 0)
                  let l:sProjectsParentFilter = l:filterMatch[1]
               endif
               let l:boolInProjectsParentSection = 1
            else
               " this is usual project section.
               " look if sProjName is like %blabla%
               let l:sPatternTmpVar = '\v\%([^%]+)\%'

               while (match(l:sProjName, l:sPatternTmpVar) >= 0)
                  "echo "1"
                  let l:tmpVarMatch = matchlist(l:sProjName, l:sPatternTmpVar)

                  let l:dirNameMatch = matchlist(l:tmpVarMatch[1], '\vdir_name\(([^)]+)\)')
                  if (len(l:dirNameMatch) > 0)
                     " get name of directory

                     let l:sDirName = simplify(a:indexerFile.'/../'.l:dirNameMatch[1])
                     let l:sDirName = <SID>_GetPathLastItem(l:sDirName)
                     let l:sProjName = substitute(l:sProjName, l:sPatternTmpVar, l:sDirName, '')
                  else
                     let l:sProjName = substitute(l:sProjName, l:sPatternTmpVar, '_unknown_var_', '')
                  endif
               endwhile


               " ---------------------


               let l:boolInProjectsParentSection = 0


               if (a:dIndexerParams['projectName'] != '')
                  if (l:sProjName == a:dIndexerParams['projectName'])
                     let l:boolInNeededProject = 1
                  else
                     let l:boolInNeededProject = 0
                  endif
               endif

               if l:boolInNeededProject
                  let l:sCurProjName = l:sProjName
                  let l:dResult[l:sCurProjName] = { 'files': [], 'paths': [], 'not_exist': [], 'pathsForCtags': [], 'pathsRoot': [] }
               endif
            endif
         else

            if l:boolInProjectsParentSection
               " parsing one project parent

               let l:lFilter = split(l:sProjectsParentFilter, ' ')
               if (len(l:lFilter) == 0)
                  let l:lFilter = ['*']
               endif
               " removing \/* from end of path
               let l:projectsParent = substitute(<SID>Trim(l:sLine), '[\\/*]\+$', '', '')

               " creating list of projects
               let l:lProjects = split(expand(l:projectsParent.'/*'), '\n')
               let l:lIndexerFilesList = []
               for l:sPrj in l:lProjects
                  if (isdirectory(l:sPrj))
                     call add(l:lIndexerFilesList, '['.substitute(l:sPrj, '^.*[\\/]\([^\\/]\+\)$', '\1', '').']')
                     for l:sCurFilter in l:lFilter
                        call add(l:lIndexerFilesList, l:sPrj.'/**/'.l:sCurFilter)
                     endfor
                     call add(l:lIndexerFilesList, '')
                  endif
               endfor
               " parsing this list
               let l:dResult = <SID>GetDirsAndFilesFromIndexerList(l:lIndexerFilesList, a:indexerFile, l:dResult, a:dIndexerParams)
               
            elseif l:boolInNeededProject
               " looks like there's path
               if l:sCurProjName == ''
                  let l:sCurProjName = 'noname'
                  let l:dResult[l:sCurProjName] = { 'files': [], 'paths': [], 'not_exist': [], 'pathsForCtags': [], 'pathsRoot': [] }
               endif

               " we should separately expand every variable
               " like $BLABLABLA
               let l:sPatt = "\\v(\\$[a-zA-Z0-9_]+)"
               let l:sUnknownPrefix = '-=UNKNOWN=-'
               while (1)
                  let l:varMatch = matchlist(l:sLine, l:sPatt)
                  " if there's any $BLABLA in string
                  if (len(l:varMatch) > 0)
                     let l:sValue = expand(l:varMatch[1])

                     if l:sValue == l:varMatch[1]
                        " unknown variable
                        call confirm('Indexer warning: unknown variable in '.a:indexerFile.': '.l:sValue)
                        let l:sValue = substitute(l:sValue, '\V$', l:sUnknownPrefix, '')
                     endif

                     " changing one slash in value to doubleslash
                     let l:sValue = substitute(l:sValue, "\\\\", "\\\\\\\\", "g")
                     " changing $BLABLA to its value (doubleslashed)
                     let l:sLine = substitute(l:sLine, l:sPatt, l:sValue, "")
                  else 
                     break
                  endif
               endwhile

               let l:sLine = substitute(l:sLine, '\V'.l:sUnknownPrefix, '$', 'g')


               let l:sTmpLine = l:sLine
               " removing last part of path (removing all after last slash)
               let l:sTmpLine = substitute(l:sTmpLine, '^\(.*\)[\\/][^\\/]\+$', '\1', 'g')
               " removing asterisks at end of line
               let l:sTmpLine = substitute(l:sTmpLine, '^\([^*]\+\).*$', '\1', '')
               " removing final slash
               let l:sTmpLine = substitute(l:sTmpLine, '[\\/]$', '', '')

               let l:dResult[l:sCurProjName].pathsRoot = <SID>ConcatLists(l:dResult[l:sCurProjName].pathsRoot, [<SID>ParsePath(l:sTmpLine)])
               let l:dResult[l:sCurProjName].paths = <SID>ConcatLists(l:dResult[l:sCurProjName].paths, [<SID>ParsePath(l:sTmpLine)])



               " -- now we should generate all subdirs
               "    (if g:indexer_getAllSubdirsFromIndexerListFile is on)

               let l:lSubPaths = []

               if a:dIndexerParams['getAllSubdirsFromIndexerListFile']
                  " getting string with all subdirs
                  let l:sSubPaths = expand(l:sTmpLine."/**/")
                  " removing final slash at end of every dir
                  let l:sSubPaths = substitute(l:sSubPaths, '\v[\\/](\n|$)', '\1', 'g')
                  " getting list from string
                  let l:lSubPaths = split(l:sSubPaths, '\n')
               endif

               


               let l:dResult[l:sCurProjName].paths = <SID>ConcatLists(l:dResult[l:sCurProjName].paths, l:lSubPaths)


               if (!<SID>_UseDirsInsteadOfFiles(a:dIndexerParams))
                  " adding every file.
                  let l:dResult[l:sCurProjName].files = <SID>ConcatLists(l:dResult[l:sCurProjName].files, split(expand(substitute(<SID>Trim(l:sLine), '\\\*\*', '**', 'g')), '\n'))
               else
                  " adding just paths. (much more faster)
                  let l:dResult[l:sCurProjName].pathsForCtags = l:dResult[l:sCurProjName].pathsRoot
               endif
            endif

         endif
      endif

   endfor

   return l:dResult
endfunction

" getting dictionary with files, paths and non-existing files from indexer
" project file
function! <SID>GetDirsAndFilesFromIndexerFile(indexerFile, dIndexerParams)
   let l:aLines = readfile(a:indexerFile)
   let l:dResult = {}
   let l:dResult = <SID>GetDirsAndFilesFromIndexerList(l:aLines, a:indexerFile, l:dResult, a:dIndexerParams)
   return l:dResult
endfunction

" getting dictionary with files, paths and non-existing files from
" project.vim's project file
function! <SID>GetDirsAndFilesFromProjectFile(projectFile, dIndexerParams)
   let l:aLines = readfile(a:projectFile)
   " if projectName is empty, then we should add files from whole projectFile
   let l:boolInNeededProject = (a:dIndexerParams['projectName'] == '' ? 1 : 0)

   let l:iOpenedBraces = 0 " current count of opened { }
   let l:iOpenedBracesAtProjectStart = 0
   let l:aPaths = [] " paths stack
   let l:sLastFoundPath = ''

   let l:dResult = {}
   let l:sCurProjName = ''

   for l:sLine in l:aLines
      " ignoring comments
      if l:sLine =~ '^#' | continue | endif

      let l:sLine = substitute(l:sLine, '#.\+$', '' ,'')
      " searching for closing brace { }
      let sTmpLine = l:sLine
      while (sTmpLine =~ '}')
         let l:iOpenedBraces = l:iOpenedBraces - 1

         " if projectName is defined and there was last brace closed, then we
         " are finished parsing needed project
         if (l:iOpenedBraces <= l:iOpenedBracesAtProjectStart) && a:dIndexerParams['projectName'] != ''
            let l:boolInNeededProject = 0
            " TODO: total break
         endif
         call remove(l:aPaths, len(l:aPaths) - 1)

         let sTmpLine = substitute(sTmpLine, '}', '', '')
      endwhile

      " searching for blabla=qweqwe
      let l:myMatch = matchlist(l:sLine, '\s*\(.\{-}\)=\(.\{-}\)\\\@<!\(\s\|$\)')
      if (len(l:myMatch) > 0)
         " now we found start of project folder or subfolder
         "
         if !l:boolInNeededProject
            if (a:dIndexerParams['projectName'] != '' && l:myMatch[1] == a:dIndexerParams['projectName'])
               let l:iOpenedBracesAtProjectStart = l:iOpenedBraces
               let l:boolInNeededProject = 1
            endif
         endif

         if l:boolInNeededProject && (l:iOpenedBraces == l:iOpenedBracesAtProjectStart)
            let l:sCurProjName = l:myMatch[1]
            let l:dResult[l:myMatch[1]] = { 'files': [], 'paths': [], 'not_exist': [], 'pathsForCtags': [], 'pathsRoot': [] }
         endif

         let l:sLastFoundPath = l:myMatch[2]
         " ADDED! Jkooij
         " Strip the path of surrounding " characters, if there are any
         let l:sLastFoundPath = substitute(l:sLastFoundPath, "\"\\(.*\\)\"", "\\1", "g")
         let l:sLastFoundPath = expand(l:sLastFoundPath) " Expand any environment variables that might be in the path
         let l:sLastFoundPath = <SID>ParsePath(l:sLastFoundPath)

      endif

      " searching for opening brace { }
      let sTmpLine = l:sLine
      while (sTmpLine =~ '{')

         if (<SID>IsAbsolutePath(l:sLastFoundPath) || len(l:aPaths) == 0)
            call add(l:aPaths, <SID>ParsePath(l:sLastFoundPath))
         else
            call add(l:aPaths, <SID>ParsePath(l:aPaths[len(l:aPaths) - 1].'/'.l:sLastFoundPath))
         endif

         let l:iOpenedBraces = l:iOpenedBraces + 1

         " adding current path to paths list if we are in needed project.
         if (l:boolInNeededProject && l:iOpenedBraces > l:iOpenedBracesAtProjectStart && isdirectory(l:aPaths[len(l:aPaths) - 1]))
            " adding to paths (that are with all subfolders)
            call add(l:dResult[l:sCurProjName].paths, l:aPaths[len(l:aPaths) - 1])
            " if last found path was absolute, then adding it to pathsRoot
            if (<SID>IsAbsolutePath(l:sLastFoundPath))
               call add(l:dResult[l:sCurProjName].pathsRoot, l:aPaths[len(l:aPaths) - 1])
            endif
         endif

         let sTmpLine = substitute(sTmpLine, '{', '', '')
      endwhile

      " searching for filename (if there's files-mode, not dir-mode)
      if (!<SID>_UseDirsInsteadOfFiles(a:dIndexerParams))
         if (l:sLine =~ '^[^={}]*$' && l:sLine !~ '^\s*$')
            " here we found something like filename
            "
            if (l:boolInNeededProject && l:iOpenedBraces > l:iOpenedBracesAtProjectStart)
               " we are in needed project
               "let l:sCurFilename = expand(<SID>ParsePath(l:aPaths[len(l:aPaths) - 1].'/'.<SID>Trim(l:sLine)))
               " CHANGED! Jkooij
               " expand() will change slashes based on 'shellslash' flag,
               " so call <SID>ParsePath() on expand() result for consistent slashes
               let l:sCurFilename = <SID>ParsePath(expand(l:aPaths[len(l:aPaths) - 1].'/'.<SID>Trim(l:sLine)))
               if (filereadable(l:sCurFilename))
                  " file readable! adding it
                  call add(l:dResult[l:sCurProjName].files, l:sCurFilename)
               elseif (!isdirectory(l:sCurFilename))
                  call add(l:dResult[l:sCurProjName].not_exist, l:sCurFilename)
               endif
            endif

         endif
      endif

   endfor

   " if there's dir-mode then let's set pathsForCtags = pathsRoot
   if (<SID>_UseDirsInsteadOfFiles(a:dIndexerParams))
      for l:sKey in keys(l:dResult)
         let l:dResult[l:sKey].pathsForCtags = l:dResult[l:sKey].pathsRoot
      endfor
      
   endif

   return l:dResult
endfunction


" parse file .vimprojects or .indexer_files
function! <SID>ParseProjectSettingsFile(sProjFileKey)

   call <SID>_AddToDebugLog(s:DEB_LEVEL__PARSE, 'function start: __ParseProjectSettingsFile__', {'filename' : s:dProjFilesParsed[ a:sProjFileKey ]["filename"]})


   let l:sVimprjKey = s:dProjFilesParsed[ a:sProjFileKey ]["sVimprjKey"]
   if (l:sVimprjKey != g:vimprj#sCurVimprjKey)
      call vimprj#applyVimprjSettings(l:sVimprjKey)
   endif

   if (s:dProjFilesParsed[ a:sProjFileKey ]["type"] == 'IndexerFile')

      let s:dProjFilesParsed[a:sProjFileKey]["projects"] = 
               \  <SID>GetDirsAndFilesFromIndexerFile(
               \     s:dProjFilesParsed[ a:sProjFileKey ]["filename"],
               \     g:vimprj#dRoots[ l:sVimprjKey ]['indexer']
               \  )

   elseif (s:dProjFilesParsed[ a:sProjFileKey ]["type"] == 'ProjectFile')

      let s:dProjFilesParsed[a:sProjFileKey]["projects"] = 
               \  <SID>GetDirsAndFilesFromProjectFile(
               \     s:dProjFilesParsed[ a:sProjFileKey ]["filename"],
               \     g:vimprj#dRoots[ l:sVimprjKey ]['indexer']
               \  )

   endif

   if (l:sVimprjKey != g:vimprj#sCurVimprjKey)
      call vimprj#applyVimprjSettings(g:vimprj#sCurVimprjKey)
   endif


   " для каждого проекта из файла с описанием проектов
   " указываем параметры:
   "     boolIndexed = 0
   "     tagsFilename - имя файла тегов
   for l:sCurProjName in keys(s:dProjFilesParsed[ a:sProjFileKey ]["projects"])
      let s:dProjFilesParsed[a:sProjFileKey]["projects"][ l:sCurProjName ]["boolIndexed"] = 0

      "let l:sTagsFileWOPath = <SID>GetKeyFromPath(a:sProjFileKey.'_'.l:sCurProjName)
      "let l:sTagsFile = s:tagsDirname.'/'.l:sTagsFileWOPath

      " если директория для тегов не указана в конфиге - значит, юзаем
      " /path/to/.vimprojects_tags/  (или ....indexer_files)
      " и каждый файл называется так же, как называется проект.
      "
      " а если указана, то все теги кладем в нее, и названия файлов
      " тегов будут длинными, типа: /path/to/tags/D__projects_myproject_vimprj__indexer_files_BK90

      if empty(s:indexer_tagsDirname)
         " директория для тегов НЕ указана
         let l:sTagsDirname = s:dProjFilesParsed[a:sProjFileKey]["filename"]."_tags"
         let l:sTagsFileWOPath = <SID>GetKeyFromPath(l:sCurProjName)
      else
         " директория для тегов указана
         let l:sTagsDirname = s:indexer_tagsDirname
         let l:sTagsFileWOPath = <SID>GetKeyFromPath(a:sProjFileKey.'_'.l:sCurProjName)
      endif

      let l:sTagsFile = l:sTagsDirname.'/'.l:sTagsFileWOPath


      if !isdirectory(l:sTagsDirname)
         call mkdir(l:sTagsDirname, "p")
      endif

      let s:dProjFilesParsed[a:sProjFileKey]["projects"][ l:sCurProjName ]["tagsFilename"] = l:sTagsFile
      let s:dProjFilesParsed[a:sProjFileKey]["projects"][ l:sCurProjName ]["tagsFilenameEscaped"]=substitute(l:sTagsFile, ' ', '\\\\\\ ', 'g')

      let l:sPathsAll = ""
      for l:sPath in s:dProjFilesParsed[a:sProjFileKey]["projects"][l:sCurProjName].paths
         if isdirectory(l:sPath)
            let l:sPathsAll .= substitute(l:sPath, ' ', '\\ ', 'g').","
         endif
      endfor
      let s:dProjFilesParsed[a:sProjFileKey]["projects"][ l:sCurProjName ]["sPathsAll"] = l:sPathsAll

   endfor

   call <SID>_AddToDebugLog(s:DEB_LEVEL__PARSE, 'function end: __ParseProjectSettingsFile__', {})
endfunction

" Update tags for all projects that owns a file.
" (now every file can be owned just by one project)
"
" param a:sFile - string like '%' or '<afile>' or something like that.
" 
function! <SID>UpdateTagsForFile(iFileNum)

   let l:iFileNum           = a:iFileNum
   let l:sVimprjKey         = g:vimprj#dFiles[ l:iFileNum ]['sVimprjKey']
   let l:boolJustAppendTags = g:vimprj#dRoots[ l:sVimprjKey ]['indexer'].ctagsJustAppendTagsAtFileSave


   "let l:sSavedFile = <SID>ParsePath(expand(a:sFile.':p'))
   let l:sSavedFile = <SID>BufName(l:iFileNum)

   "let l:sSavedFilePath = <SID>ParsePath(expand('%:p:h'))


   " для каждого проекта, в который входит файл, ...

   for l:lFileProjs in g:vimprj#dFiles[ l:iFileNum ]["projects"]
      let l:dCurProject = s:dProjFilesParsed[ l:lFileProjs.file ]["projects"][ l:lFileProjs.name ]

      " if saved file is present in non-existing filelist then moving file from non-existing list to existing list
      if (<SID>IsFileExistsInList(l:dCurProject.not_exist, l:sSavedFile))
         call remove(l:dCurProject.not_exist, index(l:dCurProject.not_exist, l:sSavedFile))
         call add(l:dCurProject.files, l:sSavedFile)
      endif

      if l:boolJustAppendTags
         call <SID>UpdateTagsForProject(l:lFileProjs.file, l:lFileProjs.name, l:sSavedFile, g:vimprj#dRoots[ l:sVimprjKey ]['indexer'])
      else
         call <SID>UpdateTagsForProject(l:lFileProjs.file, l:lFileProjs.name, "", g:vimprj#dRoots[ l:sVimprjKey ]['indexer'])
      endif

   endfor
endfunction




" ************************************************************************************************
"                    EVENT HANDLERS (OnBufSave, OnBufEnter, OnFileOpen)
" ************************************************************************************************




























" ************************************************************************************************
"                                             INIT
" ************************************************************************************************

" --------- init variables --------
"if !exists('g:indexer_defaultSettingsFilename')
   "let s:indexer_defaultSettingsFilename = ''
"else
   "let s:indexer_defaultSettingsFilename = g:indexer_defaultSettingsFilename
"endif

"if !exists('g:indexer_lookForProjectDir')
   "let s:indexer_lookForProjectDir = 1
"else
   "let s:indexer_lookForProjectDir = g:indexer_lookForProjectDir
"endif

"if !exists('g:indexer_dirNameForSearch')
   "let s:indexer_dirNameForSearch = '.vimprj'
"else
   "let s:indexer_dirNameForSearch = g:indexer_dirNameForSearch
"endif

"if !exists('g:indexer_recurseUpCount')
   "let s:indexer_recurseUpCount = 10
"else
   "let s:indexer_recurseUpCount = g:indexer_recurseUpCount
"endif

if !exists('g:indexer_tagsDirname')
   let s:indexer_tagsDirname = ''  "$HOME.'/.vimtags'
else
   let s:indexer_tagsDirname = g:indexer_tagsDirname
endif

if !exists('g:indexer_maxOSCommandLen')
   if (has('win32') || has('win64'))
      let s:indexer_maxOSCommandLen = 8000
   else
      let s:indexer_maxOSCommandLen = system("echo $(( $(getconf ARG_MAX) - $(env | wc -c) ))") - 200
   endif
else
   let s:indexer_maxOSCommandLen = g:indexer_maxOSCommandLen
endif

if !exists('g:indexer_disableCtagsWarning')
   let s:indexer_disableCtagsWarning = 0
else
   let s:indexer_disableCtagsWarning = g:indexer_disableCtagsWarning
endif

if !exists('g:indexer_debugLogLevel')
   let s:indexer_debugLogLevel = 0
else
   let s:indexer_debugLogLevel = g:indexer_debugLogLevel
endif

if !exists('g:indexer_debugLogFilename')
   let s:indexer_debugLogFilename = ''
else
   let s:indexer_debugLogFilename = g:indexer_debugLogFilename

   if !empty(s:indexer_debugLogFilename) && s:indexer_debugLogLevel > 0
      exec ':redir >> '.s:indexer_debugLogFilename
      exec ':silent echo ""'
      exec ':silent echo "**********************************************************************************************"'
      exec ':silent echo " Log opened."'
      exec ':silent echo " Vim version: '.v:version.'"'
      exec ':silent echo " Indexer version: '.g:iIndexerVersion.'"'
      exec ':silent echo " Log level: '.s:indexer_debugLogLevel.'"'
      if exists("*strftime")
         exec ':silent echo " Time: '.strftime("%c").'"'
      endif
      exec ':silent echo "**********************************************************************************************"'
      exec ':silent echo ""'
      exec ':redir END'
   endif
endif

"if !exists('g:indexer_changeCurDirIfVimprjFound')
   "let s:indexer_changeCurDirIfVimprjFound = 1
"else
   "let s:indexer_changeCurDirIfVimprjFound = g:indexer_changeCurDirIfVimprjFound
"endif





" following options can be overwrited in .vimprj folders

if !exists('g:indexer_useSedWhenAppend')
   let g:indexer_useSedWhenAppend = 1
endif

if !exists('g:indexer_indexerListFilename')
   let g:indexer_indexerListFilename = $HOME.'/.indexer_files'
endif

if !exists('g:indexer_projectsSettingsFilename')
   let g:indexer_projectsSettingsFilename = $HOME.'/.vimprojects'
endif

if !exists('g:indexer_projectName')
   let g:indexer_projectName = ''
endif

if !exists('g:indexer_enableWhenProjectDirFound')
   let g:indexer_enableWhenProjectDirFound = '1'
endif

if !exists('g:indexer_ctagsCommandLineOptions')
   let g:indexer_ctagsCommandLineOptions = '--c++-kinds=+p+l --fields=+iaS --extra=+q'
endif

if !exists('g:indexer_handlePath')
   let g:indexer_handlePath = 1
endif

if !exists('g:indexer_ctagsJustAppendTagsAtFileSave')
   if (has('win32') || has('win64'))
      let g:indexer_ctagsJustAppendTagsAtFileSave = 0
   else
      let g:indexer_ctagsJustAppendTagsAtFileSave = 1
   endif
endif

if !exists('g:indexer_ctagsDontSpecifyFilesIfPossible')
   let g:indexer_ctagsDontSpecifyFilesIfPossible = -1
endif

if !exists('g:indexer_backgroundDisabled')
   let g:indexer_backgroundDisabled = 0
endif

if !exists('g:indexer_getAllSubdirsFromIndexerListFile')
   let g:indexer_getAllSubdirsFromIndexerListFile = 0
endif

if !exists('g:indexer_ctagsWriteFilelist')
   let g:indexer_ctagsWriteFilelist = 1
endif


let s:def_useSedWhenAppend                  = g:indexer_useSedWhenAppend
let s:def_indexerListFilename               = g:indexer_indexerListFilename
let s:def_projectsSettingsFilename          = g:indexer_projectsSettingsFilename
let s:def_projectName                       = g:indexer_projectName
let s:def_enableWhenProjectDirFound         = g:indexer_enableWhenProjectDirFound
let s:def_ctagsCommandLineOptions           = g:indexer_ctagsCommandLineOptions
let s:def_ctagsJustAppendTagsAtFileSave     = g:indexer_ctagsJustAppendTagsAtFileSave
let s:def_ctagsDontSpecifyFilesIfPossible   = g:indexer_ctagsDontSpecifyFilesIfPossible
let s:def_ctagsWriteFilelist                = g:indexer_ctagsWriteFilelist
let s:def_backgroundDisabled                = g:indexer_backgroundDisabled
let s:def_handlePath                        = g:indexer_handlePath
let s:def_getAllSubdirsFromIndexerListFile  = g:indexer_getAllSubdirsFromIndexerListFile

" -------- init commands ---------

if exists(':IndexerInfo') != 2
   command -nargs=? -complete=file IndexerInfo call <SID>IndexerInfo()
endif
if exists(':IndexerDebugInfo') != 2
   command -nargs=? -complete=file IndexerDebugInfo call <SID>IndexerDebugInfo()
endif
if exists(':IndexerDebugLog') != 2
   command -nargs=? -complete=file IndexerDebugLog call <SID>IndexerDebugLog()
endif
if exists(':IndexerDebugSave') != 2
   command -nargs=? -complete=file IndexerDebugSave call <SID>IndexerDebugSave()
endif
if exists(':IndexerFiles') != 2
   command -nargs=? -complete=file IndexerFiles call <SID>IndexerFilesList()
endif
if exists(':IndexerRebuild') != 2
   command -nargs=? -complete=file IndexerRebuild call <SID>UpdateTagsForFile(bufnr('%'))
endif

call <SID>Indexer_DetectCtags()

if empty(s:dCtagsInfo['boolCtagsExists'])
   echomsg "Indexer error: Exuberant Ctags not found in PATH. You need to install Ctags to make Indexer work."
endif

let s:sLastCtagsCmd =      "** no ctags commands yet **"
let s:sLastCtagsOutput =   "** no output yet **"

" DICTIONARY for acync commands
"let s:dAsyncData = {}
let s:dAsyncTasks = {}
let s:iAsyncTaskCur = -1
let s:iAsyncTaskNext = 0
let s:iAsyncTaskLast = 0
let s:boolAsyncCommandInProgress = 0
let s:bool_OnFileOpen_executed = 0

let s:lDebug = []

let s:DEB_LEVEL__ASYNC  = 1
let s:DEB_LEVEL__PARSE  = 2
let s:DEB_LEVEL__ALL    = 3

" запоминаем начальные &tags, &path
let s:sTagsDefault = &tags
let s:sPathDefault = &path

" задаем пустые массивы с данными
let s:dProjFilesParsed = {}

"autocmd BufWritePost * call <SID>OnBufSave()




let g:indexer_dProjFilesParsed = s:dProjFilesParsed

