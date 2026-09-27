-- Paste only into a new test document; never target the user's active document.
on run argv
    tell application "Microsoft Word"
        set testDocument to make new document
        try
            paste object (text object of testDocument)
            save as testDocument file name (item 1 of argv) file format format document default add to recent files false
            set savedName to do shell script "/usr/bin/basename " & quoted form of (item 1 of argv)
            close document savedName saving no
            return "Word " & version & ": pasted into separate document, saved and closed"
        on error messageText number errorNumber
            try
                close testDocument saving no
            end try
            error messageText number errorNumber
        end try
    end tell
end run
