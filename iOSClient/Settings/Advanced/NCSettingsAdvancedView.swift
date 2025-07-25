// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2024 Aditya Tyagi
// SPDX-FileCopyrightText: 2024 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import NextcloudKit

struct NCSettingsAdvancedView: View {
    @ObservedObject var model: NCSettingsAdvancedModel
    // State variable for indicating whether the exit alert is shown.
    @State var showExitAlert: Bool = false
    // State variable for indicating whether the cache alert is shown.
    @State var showCacheAlert: Bool = false
    // State variable for indicating whether to disable crash reporter.
    @State var showCrashReporter: Bool = false

    var body: some View {
        Form {
            // file name
            Section(content: {
               NavigationLink(destination: LazyView {
                   NCFileNameView(model: NCFileNameModel(controller: model.controller))
               }) {
                   Text(NSLocalizedString("_filenamemask_", comment: ""))
               }
            }, footer: {
                Text(fileNameMaskFooter)
            })
            // Most Compatible & Enable Live Photo
            Section(content: {
                Toggle(NSLocalizedString("_format_compatibility_", comment: ""), isOn: $model.mostCompatible)
                    .tint(Color(NCBrandColor.shared.getElement(account: model.session.account)))
                    .onChange(of: model.mostCompatible) {
                        model.updateMostCompatible()
                    }
            }, footer: {
                Text(NSLocalizedString("_format_compatibility_footer_", comment: ""))
            })

            Section(content: {
                Toggle(NSLocalizedString("_upload_mov_livephoto_", comment: ""), isOn: $model.livePhoto)
                    .tint(Color(NCBrandColor.shared.getElement(account: model.session.account)))
                    .onChange(of: model.livePhoto) {
                        model.updateLivePhoto()
                    }
            }, footer: {
                Text(NSLocalizedString("_upload_mov_livephoto_footer_", comment: ""))
            })

            // Remove from Camera Roll
            Section(content: {
                Toggle(NSLocalizedString("_remove_photo_CameraRoll_", comment: ""), isOn: $model.removeFromCameraRoll)
                    .tint(Color(NCBrandColor.shared.getElement(account: model.session.account)))
                    .onChange(of: model.removeFromCameraRoll) {
                        model.updateRemoveFromCameraRoll()
                }
            }, footer: {
                Text(NSLocalizedString("_remove_photo_CameraRoll_desc_", comment: ""))
            })
            // Section : Files App
            if !NCBrandOptions.shared.disable_openin_file {
                Section(content: {
                    Toggle(NSLocalizedString("_disable_files_app_", comment: ""), isOn: $model.appIntegration)
                        .tint(Color(NCBrandColor.shared.getElement(account: model.session.account)))
                        .onChange(of: model.appIntegration) {
                            model.updateAppIntegration()
                    }
                }, footer: {
                    Text(NSLocalizedString("_disable_files_app_footer_", comment: ""))
                })
            }
            // Section: Privacy
            if !NCBrandOptions.shared.disable_crash_service {
                Section(content: {
                    Toggle(NSLocalizedString("_crashservice_title_", comment: ""), isOn: $model.crashReporter)
                        .tint(Color(NCBrandColor.shared.getElement(account: model.session.account)))
                        .onChange(of: model.crashReporter) {
                            model.updateCrashReporter()
                            showCrashReporter.toggle()
                    }
                    .alert(NSLocalizedString("_crashservice_title_", comment: ""), isPresented: $showCrashReporter, actions: {
                        Button(NSLocalizedString("OK", comment: ""), role: .cancel) {
                            model.exitNextCloud(ext: showCrashReporter)
                        }
                    }, message: {
                        Text(NSLocalizedString("_crashservice_alert_", comment: ""))
                    })
                }, header: {
                    Text(NSLocalizedString("_privacy_", comment: ""))
                }, footer: {
                    Text(NSLocalizedString("_privacy_footer_", comment: ""))
                })
            }
            // Section: Diagnostic LOG
            if !NCBrandOptions.shared.disable_log {
                Section(content: {
                    /// View Log File
                    Button(action: {
                        model.viewLogFile()
                    }, label: {
                        HStack {
                            Image(systemName: "doc.badge.gearshape")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                                .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                            Text(NSLocalizedString("_view_log_", comment: ""))
                        }
                    })
                    .tint(Color(UIColor.label))
                    // Set Log Level()
                    Picker(NSLocalizedString("_set_log_level_", comment: ""), selection: $model.selectedLogLevel) {
                        ForEach(NKLogLevel.allCases) { level in
                            Text(level.displayText).tag(level)
                        }
                    }
                    .onChange(of: model.selectedLogLevel) {
                        model.updateSelectedLogLevel()
                    }
                }, header: {
                    Text(NSLocalizedString("_diagnostics_", comment: ""))
                }, footer: {
                    Text(NSLocalizedString("_diagnostics_footer_", comment: ""))
                })
                // Set Log Level() & Capabilities
                if model.isAdminGroup {
                    Section(content: {
                        NavigationLink(destination: LazyView {
                            NCCapabilitiesView(model: NCCapabilitiesModel(controller: model.controller))
                        }) {
                            HStack {
                                Image(systemName: "list.bullet")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 25, height: 25)
                                    .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                                Text(NSLocalizedString("_capabilities_", comment: ""))
                            }
                        }
                    }, header: {
                        Text(NSLocalizedString("_capabilities_", comment: ""))
                    }, footer: {
                        Text(NSLocalizedString("_capabilities_footer_", comment: ""))
                    })
                }
            }
            // Delete in Cache & Clear Cache
            Section(content: {
                Picker(NSLocalizedString("_delete_old_files_", comment: ""), selection: $model.selectedInterval) {
                    ForEach(CacheDeletionInterval.allCases) { interval in
                        Text(interval.displayText).tag(interval)
                    }
                }
                .pickerStyle(.automatic)
                .onChange(of: model.selectedInterval) {
                    model.updateSelectedInterval()
                }
                Button(action: {
                    showCacheAlert.toggle()
                }, label: {
                    HStack {
                        Image(systemName: "xmark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                        Text(NSLocalizedString("_clear_cache_", comment: ""))
                    }
                })
                .tint(Color(UIColor.label))
                .alert(NSLocalizedString("_want_delete_cache_", comment: ""), isPresented: $showCacheAlert) {
                    Button(NSLocalizedString("_yes_", comment: ""), role: .destructive) {
                        model.clearCache()
                    }
                    Button(NSLocalizedString("_cancel_", comment: ""), role: .cancel) { }
                }
            }, header: {
                Text(NSLocalizedString("_delete_files_desc_", comment: ""))
            }, footer: {
                Text(model.footerTitle)
                    .multilineTextAlignment(.leading)
            })
            // Reset Application
            Section(content: {
                Button(action: {
                    showExitAlert.toggle()
                }, label: {
                    HStack {
                        Image(systemName: "xmark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .foregroundColor(Color(UIColor.systemRed))
                        Text(NSLocalizedString("_exit_", comment: ""))
                            .foregroundColor(Color(UIColor.systemRed))
                    }
                })
                .tint(Color(UIColor.label))
                .alert(NSLocalizedString("_want_exit_", comment: ""), isPresented: $showExitAlert) {
                    Button(NSLocalizedString("_ok_", comment: ""), role: .destructive) {
                        model.resetNextCloud()
                    }
                    Button(NSLocalizedString("_cancel_", comment: ""), role: .cancel) { }
                }
            }, footer: {
               (
                Text(NSLocalizedString("_exit_footer_", comment: ""))
                +
                Text("\n\n")
               )
            })
        }
        .navigationBarTitle(NSLocalizedString("_advanced_", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .defaultViewModifier(model)
    }

    private var fileNameMaskFooter: AttributedString {
        let boldPart = NSLocalizedString("_filenamemask_format_", comment: "")
        let localizedString = String(
            format: NSLocalizedString("_filenamemask_footer_", comment: ""),
            boldPart
        )

        var attributedString = AttributedString(localizedString)

        if let range = attributedString.range(of: boldPart) {
            attributedString[range].font = .footnote.weight(.semibold)
        }

        return attributedString
    }
}

#Preview {
    NCSettingsAdvancedView(model: NCSettingsAdvancedModel(controller: nil), showExitAlert: false, showCacheAlert: false)
}
