@echo off
rem DELETE old files
if exist BALLS.OBJ del BALLS.OBJ
if exist BALLS.EXE del BALLS.EXE
if exist BALLS.MAP del BALLS.MAP

rem COMPILE
echo Compiling...
..\TASM\BIN\TASM /zi /m2 /UT410 BALLS.ASM
if errorlevel 1 goto fail

rem LINK
echo Linking...
..\TASM\BIN\TLINK /v BALLS.OBJ
if errorlevel 1 goto fail
echo Build Successful!
goto end

:fail
echo Build Failed!

:end
