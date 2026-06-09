' Claude Usage Widget'i konsol penceresi acmadan sessizce baslatir
' Cift tiklayarak calistir, ya da Baslangic (Startup) klasorune kisayol koy.
Set sh = CreateObject("WScript.Shell")
scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "\widget.ps1""", 0, False
