' BennuGD2 Media Player - lanza el reproductor sin dejar abierta una ventana de consola
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
sh.CurrentDirectory = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "cmd /c mediaplayer.bat", 0, False
