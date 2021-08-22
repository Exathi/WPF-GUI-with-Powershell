Using Module ViewModel

# Initialize concurrentDict over synchronized hashtable. Concurrent Dictionary.AddOrUpdate handles multiple threads better than syncHash and is newer.
# Not much use since now since the progress bar value is bound and stored in ViewModel and not in the hash...
#$syncHash = [HashTable]::Synchronized(@{})
$concurrentDict = [System.Collections.Concurrent.ConcurrentDictionary[String,Object]]::new()

# Read XAML markup
[Xml]$xaml = Get-Content -Path "$PSScriptRoot\GUI.xml"
# can -replace unique source for dictionary resource source path to a relative path
# $xaml -replace "unique id", "$PSScriptRoot\relative\resource\dictionary\path.xml"

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$concurrentDict.GUI = [Windows.Markup.XamlReader]::Load($reader)

# MVVM
$concurrentDict.GUI.DataContext = [ViewModel]::new()

#===================================================
# Retrieve a list of all GUI elements to add button clicks.
# Default actions for custom window in code behind.
# Buttons that only interact with the view stay in the code behind.
#===================================================
foreach ($UIElement in $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]")) {
    [void]$concurrentDict.TryAdd($UIElement.Name, $concurrentDict.GUI.FindName($UIElement.Name))
}

$concurrentDict.subMenuFileExit.Add_Click({ $concurrentDict.GUI.Dispatcher.InvokeShutdown() })
$concurrentDict.buttonClose.Add_Click({ $concurrentDict.GUI.Dispatcher.InvokeShutdown() })
$concurrentDict.buttonMinimize.Add_Click({ $concurrentDict.GUI.WindowState = 'Minimized' })
function windowStateTrigger{
    switch ($concurrentDict.GUI.WindowState) {
        'Maximized' {$concurrentDict.GUI.WindowState = 'Normal'}
        'Normal' {$concurrentDict.GUI.WindowState = 'Maximized'}
    }
}
$concurrentDict.buttonRestore.Add_Click({ windowStateTrigger })
$concurrentDict.buttonMaximize.Add_Click({ windowStateTrigger })

# NOT MVVM. Requires dependencies if MVVM.
# No expression blend because it doesn't come natively with Windows 10
$concurrentDict.GUI.DataContext.TEMPWorkaroundTextBoxScroll = $concurrentDict.ScrollToEndTextBox
$concurrentDict.FocusedTextBox.add_TextChanged({
    if ($concurrentDict.FocusedTextBox.Text -match '\D') {
        #Disallow anything that is not a letter and prevents pasting letters
        $concurrentDict.FocusedTextBox.Text = $concurrentDict.FocusedTextBox.Text -replace '\D'

        if($concurrentDict.FocusedTextBox.Text.Length -gt 0){
            $concurrentDict.FocusedTextBox.Focus()
            $concurrentDict.FocusedTextBox.SelectionStart = $concurrentDict.FocusedTextBox.Text.Length
        }
    }
})

# If the terminal crashes after closing, you dun goofed somewhere.
$concurrentDict.GUI.ShowDialog()
#$concurrentDict.GUI.Dispatcher.InvokeAsync{$concurrentDict.GUI.ShowDialog()}.Wait()
