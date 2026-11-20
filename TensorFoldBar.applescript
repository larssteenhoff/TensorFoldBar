use AppleScript version "2.7"
use framework "Cocoa"
use scripting additions

property parent : class "NSObject"
property statusItem : missing value
property statusLine : missing value
property startItem : missing value
property pauseItem : missing value
property stopItem : missing value
property updateItem : missing value
property pollTimer : missing value
property worker : missing value
property logHandle : missing value
property phase : "Stopped"
property paused : false
property modelID : "mlx-community/Qwen3.5-2B-MLX-4bit"
property logPath : ""
property benchmarkTask : missing value
property benchmarkItem : missing value
property benchmarkResult : missing value
property benchmarkPath : ""
property benchmarkButtonTitle : "Run benchmark"
property benchmarkTokens : 64
property tokenSizeItem : missing value
property tokenSizeOptions : {}
property prefillResult : missing value
property ttftResult : missing value

on run
 set logPath to ((current application's NSHomeDirectory()) as text) & "/Library/Logs/TensorFoldBar.log"
 (current application's NSFileManager's defaultManager())'s createFileAtPath:logPath |contents|:(missing value) |attributes|:(missing value)
 set logHandle to current application's NSFileHandle's fileHandleForWritingAtPath:logPath
 logHandle's seekToEndOfFile()
 set statusItem to (current application's NSStatusBar's systemStatusBar())'s statusItemWithLength:(current application's NSVariableStatusItemLength)
 set menu to (current application's NSMenu's alloc())'s initWithTitle:"TensorFold"
 set statusLine to my addItem(menu, "TensorFold — Stopped", "statusInfo:")
 my addItem(menu, "Model: Qwen3.5 2B · 4-bit", "statusInfo:")
 menu's addItem:(current application's NSMenuItem's separatorItem())
 set startItem to my addItem(menu, "Start TensorFold", "startServer:")
 set pauseItem to my addItem(menu, "Pause", "togglePause:")
 set stopItem to my addItem(menu, "Stop and release RAM", "stopServer:")
 menu's addItem:(current application's NSMenuItem's separatorItem())
 set savedTokenCount to (current application's NSUserDefaults's standardUserDefaults())'s integerForKey:"benchmarkTokens"
 if (savedTokenCount as integer) is in {32, 64, 128, 256, 512, 1024, 2048, 4096} then set benchmarkTokens to savedTokenCount as integer
 set tokenSizeItem to my addItem(menu, "Output tokens: " & benchmarkTokens, "statusInfo:")
 set tokenMenu to (current application's NSMenu's alloc())'s initWithTitle:"Output tokens"
 set tokenSizeOptions to {}
 repeat with tokenCount in {32, 64, 128, 256, 512, 1024, 2048, 4096}
  set optionItem to my addItem(tokenMenu, tokenCount as text, "setBenchmarkTokens:")
  optionItem's setTag:(tokenCount as integer)
  set end of tokenSizeOptions to optionItem
 end repeat
 tokenSizeItem's setSubmenu:tokenMenu
 set benchmarkItem to my addItem(menu, "Run benchmark", "runBenchmark:")
 set benchmarkResult to my addItem(menu, "Benchmark: not run yet", "statusInfo:")
 benchmarkResult's setHidden:true
 set prefillResult to my addItem(menu, "Prefill: unavailable", "statusInfo:")
 set ttftResult to my addItem(menu, "Time to first token: unavailable", "statusInfo:")
 my hideBenchmarkResults()
 set benchmarkPath to ((current application's NSHomeDirectory()) as text) & "/Library/Logs/TensorFoldBar-benchmark.txt"
 menu's addItem:(current application's NSMenuItem's separatorItem())
 my addItem(menu, "Copy API URL", "copyURL:")
 my addItem(menu, "Show log…", "showLog:")
 set updateItem to my addItem(menu, "Update TensorFold to latest…", "updateEngine:")
 menu's addItem:(current application's NSMenuItem's separatorItem())
 my addItem(menu, "Quit TensorFold Bar", "quitApp:")
 statusItem's setMenu:menu
 set pollTimer to current application's NSTimer's scheduledTimerWithTimeInterval:3 target:me selector:"refresh:" userInfo:(missing value) repeats:true
 my refresh:(missing value)
end run

on addItem(theMenu, theTitle, theAction)
 set menuEntry to (current application's NSMenuItem's alloc())'s initWithTitle:theTitle action:theAction keyEquivalent:""
 if theAction is not "" then menuEntry's setTarget:me
 theMenu's addItem:menuEntry
 return menuEntry
end addItem

on binaryPath()
 return (((current application's NSBundle's mainBundle())'s resourcePath()) as text) & "/runtime/bin/tensorfold-native"
end binaryPath

on launchWorker(args)
 set worker to (current application's NSTask's alloc())'s init()
 worker's setLaunchPath:(my binaryPath())
 worker's setArguments:args
 worker's setStandardOutput:logHandle
 worker's setStandardError:logHandle
 worker's |launch|()
end launchWorker

on startServer:sender
 if worker is not missing value then return
 try
  set phase to "Downloading/checking model"
  my launchWorker({"pull", modelID & "@93760be4f1f69842a46bc13dbdc0f19e291392a3"})
 on error err
  set worker to missing value
  set phase to "Could not start — see log"
  set alertBox to current application's NSAlert's new()
  alertBox's setMessageText:"TensorFold could not start"
  alertBox's setInformativeText:err
  alertBox's runModal()
 end try
 my refresh:(missing value)
end startServer:

on togglePause:sender
 if worker is missing value then return
 if phase is not "Running" then return
 if paused then
  if (worker's resume()) as boolean then set paused to false
 else
  if (worker's suspend()) as boolean then set paused to true
 end if
 my refresh:(missing value)
end togglePause:

on stopServer:sender
 my cancelBenchmark()
 if worker is not missing value then
  if paused then worker's resume()
  if (worker's isRunning()) as boolean then
   worker's terminate()
   set paused to false
   set phase to "Stopping"
   my refresh:(missing value)
   return
  end if
 end if
 set worker to missing value
 set paused to false
 set phase to "Stopped"
 my refresh:(missing value)
end stopServer:

on refresh:sender
 if benchmarkTask is not missing value then
  if not ((benchmarkTask's isRunning()) as boolean) then
   if ((benchmarkTask's terminationStatus()) as integer) is 0 then
    set resultText to current application's NSString's stringWithContentsOfFile:benchmarkPath encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
    if resultText is not missing value then
     set resultRows to resultText's componentsSeparatedByString:(current application's NSString's stringWithString:(character id 10))
     if (resultRows's |count|()) as integer is not 3 then error "Incomplete benchmark results"
     benchmarkResult's setTitle:(resultRows's objectAtIndex:0)
     prefillResult's setTitle:(resultRows's objectAtIndex:1)
     ttftResult's setTitle:(resultRows's objectAtIndex:2)
     benchmarkResult's setHidden:false
     prefillResult's setHidden:false
     ttftResult's setHidden:false
     set benchmarkButtonTitle to "Run benchmark"
    else
     set benchmarkButtonTitle to "Benchmark failed — retry"
    end if
   else
    my hideBenchmarkResults()
    set benchmarkButtonTitle to "Benchmark failed — retry"
   end if
   set benchmarkTask to missing value
  end if
 end if
 if worker is not missing value then
  if not ((worker's isRunning()) as boolean) then
   set resultCode to (worker's terminationStatus()) as integer
   set worker to missing value
   if phase is "Downloading/checking model" and resultCode is 0 then
    try
     my launchWorker({"serve", modelID, "--name", "local-model", "--host", "127.0.0.1", "--port", "8080", "--context", "8192", "--no-thinking", "--no-update-check"})
     set phase to "Running"
    on error
     set worker to missing value
     set phase to "Start failed — see log"
    end try
   else if phase is "Updating" then
    if resultCode is 0 then
     set phase to "Updated — ready to start"
    else
     set phase to "Update failed — see log"
    end if
   else if phase is "Stopping" then
    set phase to "Stopped"
   else
    set phase to "Exited (" & resultCode & ") — see log"
   end if
   set paused to false
  end if
 end if
 set labelText to phase
 if paused then set labelText to "Paused"
 set ramText to my availableRAM()
 set marker to "○"
 if worker is not missing value then set marker to "●"
 if paused then set marker to "Ⅱ"
 (statusItem's button())'s setTitle:("TF " & marker & " · " & ramText & " GB available")
 set dotColor to current application's NSColor's secondaryLabelColor()
 if phase is "Running" then set dotColor to current application's NSColor's systemGreenColor()
 if paused then set dotColor to current application's NSColor's systemOrangeColor()
 if phase is "Updating" or phase is "Downloading/checking model" then set dotColor to current application's NSColor's systemOrangeColor()
 set statusTitle to (current application's NSMutableAttributedString's alloc())'s initWithString:("● TensorFold — " & labelText)
 statusTitle's addAttribute:(current application's NSForegroundColorAttributeName) value:(current application's NSColor's labelColor()) range:{location:0, |length|:(statusTitle's |length|())}
 statusTitle's addAttribute:(current application's NSForegroundColorAttributeName) value:dotColor range:{location:0, |length|:1}
 statusLine's setAttributedTitle:statusTitle
 startItem's setEnabled:(worker is missing value)
 pauseItem's setEnabled:(phase is "Running")
 stopItem's setEnabled:(worker is not missing value)
 updateItem's setEnabled:(worker is missing value)
 benchmarkItem's setEnabled:(phase is "Running" and not paused and benchmarkTask is missing value)
 tokenSizeItem's setTitle:("Output tokens: " & benchmarkTokens)
 tokenSizeItem's setEnabled:(benchmarkTask is missing value)
 repeat with optionItem in tokenSizeOptions
  if (optionItem's tag() as integer) is benchmarkTokens then
   optionItem's setState:1
  else
   optionItem's setState:0
  end if
  optionItem's setEnabled:(benchmarkTask is missing value)
 end repeat
 if benchmarkTask is not missing value then
  benchmarkItem's setTitle:"Benchmark running…"
 else
  benchmarkItem's setTitle:benchmarkButtonTitle
 end if
 if benchmarkTask is not missing value then pauseItem's setEnabled:false
 if paused then
  pauseItem's setTitle:"Resume"
 else
  pauseItem's setTitle:"Pause"
 end if
end refresh:

on statusInfo:sender
 -- Informational row stays enabled so macOS does not dim its status color.
end statusInfo:

on runBenchmark:sender
 if phase is not "Running" or paused or benchmarkTask is not missing value then return
 my hideBenchmarkResults()
 set benchmarkButtonTitle to "Run benchmark"
 set resourceDir to ((current application's NSBundle's mainBundle())'s resourcePath()) as text
 try
  set benchmarkTask to current application's NSTask's new()
  benchmarkTask's setLaunchPath:"/usr/bin/ruby"
  benchmarkTask's setArguments:{resourceDir & "/benchmark.rb", benchmarkPath, benchmarkTokens as text}
  benchmarkTask's setStandardOutput:logHandle
  benchmarkTask's setStandardError:logHandle
  benchmarkTask's |launch|()
 on error
  set benchmarkTask to missing value
  set benchmarkButtonTitle to "Benchmark failed — retry"
 end try
 my refresh:(missing value)
end runBenchmark:

on cancelBenchmark()
 if benchmarkTask is not missing value then
  if (benchmarkTask's isRunning()) as boolean then benchmarkTask's terminate()
  set benchmarkTask to missing value
  my hideBenchmarkResults()
  set benchmarkButtonTitle to "Run benchmark"
 end if
end cancelBenchmark

on hideBenchmarkResults()
 benchmarkResult's setHidden:true
 if prefillResult is not missing value then prefillResult's setHidden:true
 if ttftResult is not missing value then ttftResult's setHidden:true
end hideBenchmarkResults

on setBenchmarkTokens:sender
 if benchmarkTask is not missing value then return
 set benchmarkTokens to sender's tag() as integer
 (current application's NSUserDefaults's standardUserDefaults())'s setInteger:benchmarkTokens forKey:"benchmarkTokens"
 my hideBenchmarkResults()
 my refresh:(missing value)
end setBenchmarkTokens:

on availableRAM()
 try
  -- Free + inactive + speculative pages: reclaimable memory estimate.
  set memoryTask to current application's NSTask's new()
  set pipeOut to current application's NSPipe's pipe()
  memoryTask's setLaunchPath:"/bin/sh"
  memoryTask's setArguments:{"-c", "/usr/bin/vm_stat | /usr/bin/awk 'NR==1 { for(i=1;i<=NF;i++) if($i==\"of\") p=$(i+1) } /^Pages free:|^Pages inactive:|^Pages speculative:/ { gsub(/[^0-9]/,\"\",$NF); n+=$NF } END { printf \"%.1f\", n*p/1073741824 }'"}
  memoryTask's setStandardOutput:pipeOut
  memoryTask's |launch|()
  set outputData to (pipeOut's fileHandleForReading())'s readDataToEndOfFile()
  return ((current application's NSString's alloc())'s initWithData:outputData encoding:(current application's NSUTF8StringEncoding)) as text
 on error
  return "?"
 end try
end availableRAM

on copyURL:sender
 set pb to current application's NSPasteboard's generalPasteboard()
 pb's clearContents()
 pb's setString:"http://127.0.0.1:8080/v1" forType:(current application's NSPasteboardTypeString)
end copyURL:

on showLog:sender
 (current application's NSWorkspace's sharedWorkspace())'s openFile:logPath
end showLog:

on updateEngine:sender
 if worker is not missing value then return
 set resourceDir to (current application's NSBundle's mainBundle()'s resourcePath()) as text
 set worker to current application's NSTask's new()
 worker's setLaunchPath:"/bin/bash"
 worker's setArguments:{resourceDir & "/update.sh", resourceDir & "/runtime"}
 worker's setStandardOutput:logHandle
 worker's setStandardError:logHandle
 set phase to "Updating"
 try
  worker's |launch|()
 on error
  set worker to missing value
  set phase to "Update failed — see log"
 end try
 my refresh:(missing value)
end updateEngine:

on quitApp:sender
 my cancelBenchmark()
 if worker is not missing value then
  if paused then worker's resume()
  if (worker's isRunning()) as boolean then worker's terminate()
 end if
 continue quit
end quitApp:

on quit
 my cancelBenchmark()
 if worker is not missing value then
  if paused then worker's resume()
  if (worker's isRunning()) as boolean then worker's terminate()
 end if
 if pollTimer is not missing value then pollTimer's invalidate()
 continue quit
end quit
