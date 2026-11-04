import Foundation

// Privileged subcommand: when launched as root with --vdm-dfu / --vdm-reboot, run the VDM helper and exit
// before any UI starts. Invoked by the app itself via administrator privileges; otherwise the app runs.
let arguments = CommandLine.arguments
if arguments.count >= 2, arguments[1] == "--vdm-dfu" || arguments[1] == "--vdm-reboot" {
    exit(VDMTool.run(reboot: arguments[1] == "--vdm-reboot"))
}
MacOSStudioApp.main()
