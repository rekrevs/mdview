-- Run against a dedicated mdview instance displaying reader-checks/document.md.
-- Requires macOS Accessibility permission for the invoking terminal.
on run argv
    set testPID to (item 1 of argv) as integer
    set savedClipboard to the clipboard as record
    try
        tell application "System Events"
            tell (first application process whose unix id is testPID)
                set frontmost to true
                delay 0.2
                if (count of text fields of group 1 of window "document.md") > 0 then
                    key code 53
                    delay 0.2
                end if
                if (count of scroll areas of group 1 of window "document.md") > 0 then
                    keystroke "t" using {command down, option down}
                    delay 0.2
                end if
                keystroke "f" using command down
                delay 0.3
                if (count of text fields of group 1 of window "document.md") is not 1 then error "Cmd+F did not open Find"
                keystroke "bold text"
                delay 0.4
                if value of static text 1 of group 1 of window "document.md" is not "1 of 2" then error "Find did not focus or match across formatting"
                keystroke "g" using command down
                delay 0.2
                if value of static text 1 of group 1 of window "document.md" is not "2 of 2" then error "Cmd+G did not advance"
                keystroke "g" using {command down, shift down}
                delay 0.2
                if value of static text 1 of group 1 of window "document.md" is not "1 of 2" then error "Cmd+Shift+G did not go back"
                key code 36
                delay 0.2
                if value of static text 1 of group 1 of window "document.md" is not "2 of 2" then error "Return did not advance"
                key code 36 using shift down
                delay 0.2
                if value of static text 1 of group 1 of window "document.md" is not "1 of 2" then error "Shift+Return did not go back"
                key code 53
                delay 0.2
                if (count of text fields of group 1 of window "document.md") is not 0 then error "Escape did not dismiss Find"
                log "PASS Find keyboard sequence"
                keystroke "a" using command down
                keystroke "c" using command down
                delay 0.3
                set copied to the clipboard as text
                if copied does not contain "Alpha first paragraph." or copied does not contain "Bravo second paragraph." or copied does not contain "$E=mc^2$" then error "Cmd+A/C clipboard incomplete"
                log "PASS Cmd+A/C"
                keystroke "t" using {command down, option down}
                delay 0.2
                set outlineShown to count of scroll areas of group 1 of window "document.md"
                keystroke "t" using {command down, option down}
                delay 0.2
                set outlineHidden to count of scroll areas of group 1 of window "document.md"
                if outlineShown <= outlineHidden then error "Outline shortcut did not toggle sidebar"
                log "PASS outline"
                -- The actual local Markdown link opens through NSDocumentController.
                click UI element "Local" of group 4 of group "Markdown document" of UI element 1 of scroll area 1 of group 1 of group 1 of group 1 of window "document.md"
                delay 0.8
                log "Clicked local link"
                if (name of windows) does not contain "other file.markdown" then error "Local link did not open second document"
                if (name of windows) does not contain "document.md" then error "Opening local link replaced first document"
            end tell
        end tell
        set the clipboard to savedClipboard
        return "PASS release app: Cmd+F, focused typing, match count, Cmd+G, Shift+Cmd+G, Return, Shift+Return, Escape, Cmd+A/C, outline toggle, relative link and independent document windows (12 checks)"
    on error messageText number errorNumber
        set the clipboard to savedClipboard
        error messageText number errorNumber
    end try
end run
