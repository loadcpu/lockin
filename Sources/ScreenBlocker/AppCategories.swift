import SwiftUI

enum AppCategory: String, CaseIterable, Codable, Identifiable {
    case work          = "Work"
    case development   = "Development"
    case communication = "Communication"
    case social        = "Social"
    case entertainment = "Entertainment"
    case creative      = "Creative"
    case system        = "System"
    case other         = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .work:          return "briefcase.fill"
        case .development:   return "terminal.fill"
        case .communication: return "message.fill"
        case .social:        return "person.2.fill"
        case .entertainment: return "play.tv.fill"
        case .creative:      return "paintbrush.fill"
        case .system:        return "gearshape.fill"
        case .other:         return "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .work:          return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .development:   return Color(red: 0.29, green: 0.56, blue: 0.96)
        case .communication: return Color(red: 0.54, green: 0.34, blue: 0.96)
        case .social:        return Color(red: 1.00, green: 0.62, blue: 0.04)
        case .entertainment: return Color(red: 0.96, green: 0.26, blue: 0.21)
        case .creative:      return Color(red: 0.96, green: 0.18, blue: 0.56)
        case .system:        return Color(red: 0.55, green: 0.55, blue: 0.60)
        case .other:         return Color(red: 0.78, green: 0.78, blue: 0.80)
        }
    }
}

let defaultCategoryMappings: [String: AppCategory] = [
    // Development
    "com.apple.dt.Xcode":                       .development,
    "com.microsoft.VSCode":                     .development,
    "com.microsoft.VSCodeInsiders":             .development,
    "com.jetbrains.intellij.ce":                .development,
    "com.jetbrains.intellij":                   .development,
    "com.jetbrains.WebStorm":                   .development,
    "com.jetbrains.PyCharm":                    .development,
    "com.jetbrains.RubyMine":                   .development,
    "com.jetbrains.CLion":                      .development,
    "com.jetbrains.GoLand":                     .development,
    "com.apple.Terminal":                       .development,
    "com.googlecode.iterm2":                    .development,
    "com.github.wez.wezterm":                   .development,
    "dev.warp.Warp-Stable":                     .development,
    "com.sequelpro.SequelPro":                  .development,
    "com.tinyapp.TablePlus":                    .development,
    "com.postmanlabs.mac":                      .development,
    "io.insomnia.desktop":                      .development,
    "com.github.GitHub":                        .development,
    "com.sublimetext.4":                        .development,
    "com.panic.Nova":                           .development,
    "io.cursor.Cursor":                         .development,
    "io.zed.zed-preview":                       .development,
    "dev.zed.zed":                              .development,

    // Communication
    "com.tinyspeck.slackmacgap":               .communication,
    "com.microsoft.teams2":                     .communication,
    "us.zoom.xos":                              .communication,
    "com.apple.mail":                           .communication,
    "com.microsoft.Outlook":                    .communication,
    "com.apple.FaceTime":                       .communication,
    "com.apple.iChat":                          .communication,
    "com.hnc.Discord":                          .communication,
    "com.hammerandchisel.discord":              .communication,
    "ru.keepcoder.Telegram":                    .communication,
    "net.whatsapp.WhatsApp":                    .communication,
    "com.facebook.archon":                      .communication,
    "com.loom.desktop":                         .communication,
    "com.mimestream.Mimestream":                .communication,
    "com.superhuman.Superhuman":                .communication,
    "com.apple.Shortcuts":                      .communication,

    // Social
    "com.twitter.twitter-mac":                 .social,
    "com.reddit.app.reddit":                    .social,
    "com.burbn.instagram":                      .social,
    "com.facebook.Facebook":                    .social,
    "com.linkedin.LinkedIn":                    .social,
    "com.bereal.BeReal":                        .social,
    "com.mastodon.app":                         .social,

    // Entertainment
    "com.spotify.client":                       .entertainment,
    "com.apple.Music":                          .entertainment,
    "com.apple.TV":                             .entertainment,
    "com.netflix.Netflix":                      .entertainment,
    "com.apple.podcasts":                       .entertainment,
    "com.twitch.twitch":                        .entertainment,
    "tv.plex.desktop":                          .entertainment,
    "com.steam.steamapp":                       .entertainment,
    "com.valvesoftware.steam":                  .entertainment,
    "com.epicgames.EpicGamesLauncher":          .entertainment,

    // Creative
    "com.adobe.Photoshop":                      .creative,
    "com.adobe.Illustrator":                    .creative,
    "com.adobe.After-Effects":                  .creative,
    "com.adobe.Premiere":                       .creative,
    "com.adobe.InDesign":                       .creative,
    "com.adobe.Lightroom":                      .creative,
    "com.bohemiancoding.sketch3":               .creative,
    "com.figma.Desktop":                        .creative,
    "com.apple.garageband10":                   .creative,
    "com.apple.logic10":                        .creative,
    "com.apple.FinalCut":                       .creative,
    "com.blackmagic-design.DaVinciResolve":     .creative,
    "com.canva.mac":                            .creative,
    "com.pixelmator.pixelmatorphoto":           .creative,
    "com.affinity.designer2":                   .creative,
    "com.affinity.photo2":                      .creative,
    "com.affinity.publisher2":                  .creative,
    "com.blender.blender":                      .creative,

    // Work
    "com.microsoft.Word":                       .work,
    "com.microsoft.Excel":                      .work,
    "com.microsoft.Powerpoint":                 .work,
    "com.apple.iWork.Pages":                    .work,
    "com.apple.iWork.Numbers":                  .work,
    "com.apple.iWork.Keynote":                  .work,
    "com.notion.id":                            .work,
    "com.airtable.macdesktop":                  .work,
    "com.linear.linear":                        .work,
    "com.basecamp.basecamp3":                   .work,
    "com.asana.asana":                          .work,
    "com.obsidian.md":                          .work,
    "md.obsidian":                              .work,
    "com.bear.app":                             .work,
    "com.apple.Notes":                          .work,
    "com.evernote.Evernote":                    .work,
    "io.craft.CraftDesktopApp":                 .work,
    "com.culturedcode.ThingsMac":               .work,
    "com.omnigroup.OmniFocus3":                 .work,
    "com.todoist.mac.Todoist":                  .work,

    // System
    "com.apple.finder":                         .system,
    "com.apple.systempreferences":              .system,
    "com.apple.ActivityMonitor":                .system,
    "com.apple.DiskUtility":                    .system,
    "com.apple.Console":                        .system,
    "com.apple.appstore":                       .system,
    "com.apple.installer":                      .system,
    "com.apple.Preview":                        .system,
    "com.apple.ScreenSaver.Engine":             .system,
    "com.apple.Spotlight":                      .system,

    // Web domains – entertainment
    "youtube.com":                              .entertainment,
    "twitch.tv":                                .entertainment,
    "netflix.com":                              .entertainment,
    "hulu.com":                                 .entertainment,
    "disneyplus.com":                           .entertainment,
    "primevideo.com":                           .entertainment,
    "spotify.com":                              .entertainment,
    "soundcloud.com":                           .entertainment,
    "9gag.com":                                 .entertainment,
    "buzzfeed.com":                             .entertainment,

    // Web domains – social
    "twitter.com":                              .social,
    "x.com":                                    .social,
    "reddit.com":                               .social,
    "instagram.com":                            .social,
    "facebook.com":                             .social,
    "tiktok.com":                               .social,
    "linkedin.com":                             .social,
    "mastodon.social":                          .social,
    "threads.net":                              .social,
    "pinterest.com":                            .social,
    "tumblr.com":                               .social,
    "snapchat.com":                             .social,
    "news.ycombinator.com":                     .social,

    // Web domains – development
    "github.com":                               .development,
    "gitlab.com":                               .development,
    "stackoverflow.com":                        .development,
    "developer.apple.com":                      .development,
    "developer.mozilla.org":                    .development,
    "npmjs.com":                                .development,
    "crates.io":                                .development,
    "pypi.org":                                 .development,
    "hub.docker.com":                           .development,
    "docs.swift.org":                           .development,
    "swift.org":                                .development,
    "codepen.io":                               .development,
    "jsfiddle.net":                             .development,

    // Web domains – work
    "notion.so":                                .work,
    "linear.app":                               .work,
    "app.asana.com":                            .work,
    "trello.com":                               .work,
    "monday.com":                               .work,
    "airtable.com":                             .work,
    "docs.google.com":                          .work,
    "sheets.google.com":                        .work,
    "slides.google.com":                        .work,
    "drive.google.com":                         .work,
    "calendar.google.com":                      .work,
    "mail.google.com":                          .work,
    "figma.com":                                .creative,
    "canva.com":                                .creative,

    // Web domains – communication
    "slack.com":                                .communication,
    "discord.com":                              .communication,
    "teams.microsoft.com":                      .communication,
    "zoom.us":                                  .communication,
    "meet.google.com":                          .communication,
    "web.telegram.org":                         .communication,
    "web.whatsapp.com":                         .communication,
]
