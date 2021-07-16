# Powershell 5.1 and WPF
An attempt at learning WPF with Powershell, along with VSCode, Git and, Github.

This went from a simple GUI in Notepad++ from [FoxDeploy](https://www.foxdeploy.com/blog/part-v-powershell-guis-responsive-apps-with-progress-bars.html) to, hopefully, something resembling MVVM.

### **Why?**

Many who are in the IT field, or have C# in their toolbelts, would have written their GUI project in another langauge. I've seen many attempts at stackoverflow, with comments that say *move onto C#*, *use a proper tool for it*, *it's easier in C#*. I'm not qualified to judge, but I'd assume they're correct.

However, I, am currently not in the IT field and *don't know any better*. This was written because I wanted to learn. I have no formal training in C#. I am self taught in Powershell. Fortunately the syntax between Powershell and C# closely resemble each other. As many have said, Powershell is a gateway drug to C#.

# How To Open
Run with Powershell "Open GUI.ps1"

# Module Explanations
### **Modules in $env:PSModulePath**
1. Modules\RunspacePool\RunspacePool.psm1
    - For simulated background tasks and I didn't want to depend on PoshRSJobs.
2. Modules\ViewModel\ViewModel.psm1
    - Requires assemblies **PresentationFramework** and **PresentationCore** to be loaded first.
3. Modules\ViewModel\ViewModel.psd1
    - includes **ViewModelHelper.psm1** as a nested module. Nested modules in .psd1 files are loaded before the root .psm1 file.
4. Modules\ViewModel\ViewModelHelper.psm1
    - Since classes in Powershell are parsed before assemblies are loaded, we need a helper module to load the required assemblies.

# Notes
#### **Buttons**
- Buttons that only act on the view should stay on the view code behind, not the view model. Custom close, maximize, restore, minimize in the code behind are considered fine.

https://stackoverflow.com/questions/4671368/binding-the-windowstate-property-of-a-window-in-wpf-using-mvvm

- Button states must be refreshed manually if task is on another runspace/thread by calling:

```powershell
[System.Windows.Input.CommandManager]::InvalidateRequerySuggested()
```

https://stackoverflow.com/questions/50927967/relaycommand-change-canexecute-automatic

#### **Context Menu**

Context Menu's are not part of the visual tree, use PlacementTarget.property, RelativeSource to find the datacontext.

https://stackoverflow.com/questions/9880589/bind-to-selecteditems-from-datagrid-or-listbox-in-mvvm

# Helpful References

RelayCommand

https://github.com/nohwnd/WpfToolkit

Snake

https://gist.github.com/nikonthethird/2ab6bfad9a81d5fe127fd0d1c2844b7c

Minesweeper

https://gist.github.com/nikonthethird/4e410ac3c04ea6633043a5cb7be1d717

Starter GUI

https://www.foxdeploy.com/blog/part-v-powershell-guis-responsive-apps-with-progress-bars.html

Xaml MenuItem ControlTemplate

https://stackoverflow.com/questions/24698755/how-to-change-the-background-of-the-menuitem-on-mouseover-in-wpf

