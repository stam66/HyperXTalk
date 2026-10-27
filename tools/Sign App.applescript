-- Sign App.applescript — AppleScript droplet front end for sign-mac-app.sh
--
-- Save this with Script Editor as an Application (File > Export…, File Format:
-- Application).  Then either:
--   * drop one or more .app bundles onto the applet, or
--   * double-click it and pick an app from the file dialog.
--
-- It looks for sign-mac-app.sh in this order:
--   1. inside the applet itself:  Sign App.app/Contents/Resources/sign-mac-app.sh
--   2. in the same folder as the applet
--   3. ~/bin/sign-mac-app.sh
--   4. /usr/local/bin/sign-mac-app.sh

on run
	set theApp to choose file with prompt "Choose the app to code-sign:" of type {"com.apple.application-bundle"}
	signApps({theApp})
end run

on open theItems
	signApps(theItems)
end open

on signApps(theItems)
	set scriptPath to findSigner()
	if scriptPath is "" then
		display alert "sign-mac-app.sh not found" message ¬
			"Put sign-mac-app.sh next to this applet, inside its Contents/Resources folder, or in ~/bin." as critical
		return
	end if
	
	set identityArg to chooseIdentity()
	if identityArg is false then return
	
	repeat with anItem in theItems
		set appPath to POSIX path of anItem
		if appPath does not end with ".app/" and appPath does not end with ".app" then
			display alert "Not an app bundle" message appPath as warning
		else
			try
				set cmd to quoted form of scriptPath & " " & quoted form of appPath & " --quiet"
				if identityArg is not "" then set cmd to cmd & " --identity " & quoted form of identityArg
				set output to do shell script cmd
				display dialog output with title "Code signing finished" buttons {"OK"} default button "OK" with icon note
			on error errMsg number errNum
				display dialog "Signing failed (" & errNum & "):" & return & return & errMsg ¬
					with title "Code signing failed" buttons {"OK"} default button "OK" with icon stop
			end try
		end if
	end repeat
end signApps

-- Returns "" for ad-hoc, a Developer ID string, or false if the user cancelled.
on chooseIdentity()
	set theChoice to button returned of (display dialog ¬
		"Sign with an ad-hoc signature (works on this Mac only) or a Developer ID certificate from your keychain?" ¬
		with title "Sign App" buttons {"Cancel", "Developer ID…", "Ad-hoc"} default button "Ad-hoc")
	if theChoice is "Ad-hoc" then return ""
	
	-- List code-signing identities in the keychain
	set identityLines to {}
	try
		set rawList to do shell script "security find-identity -v -p codesigning | sed -n 's/^ *[0-9]*) [0-9A-F]* \"\\(.*\\)\"$/\\1/p'"
		set identityLines to paragraphs of rawList
	end try
	if identityLines is {} or identityLines is {""} then
		display alert "No code-signing identities found" message ¬
			"Install a Developer ID Application certificate in your keychain, or use Ad-hoc." as warning
		return false
	end if
	set picked to choose from list identityLines with prompt "Choose a signing identity:" without multiple selections allowed
	if picked is false then return false
	return item 1 of picked
end chooseIdentity

on findSigner()
	set candidates to {}
	try
		set me_path to POSIX path of (path to me)
		-- 1. inside the applet bundle
		set end of candidates to me_path & "Contents/Resources/sign-mac-app.sh"
		-- 2. same folder as the applet / script
		set parentDir to do shell script "dirname " & quoted form of me_path
		set end of candidates to parentDir & "/sign-mac-app.sh"
	end try
	set end of candidates to POSIX path of (path to home folder) & "bin/sign-mac-app.sh"
	set end of candidates to "/usr/local/bin/sign-mac-app.sh"
	repeat with c in candidates
		try
			do shell script "test -x " & quoted form of (c as text)
			return c as text
		end try
	end repeat
	return ""
end findSigner
