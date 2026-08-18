#!/bin/bash
set -uo pipefail



#############################
# reinstall firefox in flatpak
#############################

reinstall_firefox(){
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

  flatpak uninstall --delete-data -y org.mozilla.firefox
  flatpak uninstall --unused -y
  rm -rf "$HOME/.var/app/org.mozilla.firefox" # double check
  flatpak repair


  # global permission
  flatpak override --user --nofilesystem=home --nofilesystem=host --share=network --unshare=ipc --nodevice=all --nosocket=x11 --nosocket=fallback-x11 --disallow=bluetooth --nosocket=session-bus --nosocket=system-bus --nodevice=input --env=OPENSSL_CONF=~/.local/share/flatpak-security/openssl.cnf --filesystem=~/.local/share/flatpak-security/openssl.cnf:ro --no-talk-name=org.freedesktop.Flatpak

  # install
  flatpak --user install flathub org.mozilla.firefox -y
  
  # permission setting
  flatpak override --user \
	  --nofilesystem=xdg-config/gtk-3.0 \
	  --nofilesystem=/run/.heim_org.h5l.kcm-socket \
	  --nofilesystem=xdg-run/speech-dispatcher \
	  --unshare=ipc \
	  --nosocket=pcsc \
	  --nosocket=cups \
	  --nodevice=all \
	  --share=network \
	  org.mozilla.firefox
}


reinstall_firefox







############
# user.js
############


PROFILE_BASE="$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox"
shopt -s nullglob

USER_JS_CONTENT=$(cat <<'EOF'
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("beacon.enabled", false);
user_pref("browser.formfill.enable", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.ping-centre.telemetry", false);
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.selfsupport.url", "");
user_pref("browser.urlbar.suggest.searches", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("device.sensors.enabled", false);
user_pref("dom.battery.enabled", false);
user_pref("dom.event.clipboardevents.enabled", false);
user_pref("dom.gamepad.enabled", false);
user_pref("dom.security.https_only_mode", true);
user_pref("dom.security.https_only_mode_send_http_background_request", false);
user_pref("extensions.pocket.enabled", false);
user_pref("geo.enabled", false);
user_pref("media.autoplay.default", 5);
user_pref("media.peerconnection.enabled", false);
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);
user_pref("network.cookie.cookieBehavior", 5);
user_pref("network.cookie.lifetime.policy", 2);
user_pref("network.dns.disableIPv6", true);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.dns.echconfig.enabled", true);
user_pref("network.dns.http3.echconfig.enabled", true);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.prefetch-next", false);
user_pref("network.trr.mode", 0);
user_pref("privacy.clearOnShutdown.cache", true);
user_pref("privacy.clearOnShutdown.cookies", true);
user_pref("privacy.clearOnShutdown.downloads", true);
user_pref("privacy.clearOnShutdown.formdata", true);
user_pref("privacy.clearOnShutdown.history", true);
user_pref("privacy.clearOnShutdown.offlineApps", true);
user_pref("privacy.clearOnShutdown.sessions", true);
user_pref("privacy.firstparty.isolate", true);
user_pref("privacy.globalprivacycontrol.enabled", true);
user_pref("privacy.query_stripping.enabled", true);
user_pref("privacy.query_stripping.enabled.pbmode", true);
user_pref("privacy.resistFingerprinting", true);
user_pref("privacy.sanitize.sanitizeOnShutdown", true);
user_pref("privacy.window.maxInnerHeight", 900);
user_pref("privacy.window.maxInnerWidth", 1600);
user_pref("security.tls.version.fallback-limit", 4);
user_pref("security.tls.version.min", 4);
user_pref("signon.rememberSignons", true);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("webgl.disabled", true);
user_pref("privacy.clearOnShutdown.cache", true);
user_pref("privacy.clearOnShutdown.cookies", true);
user_pref("privacy.clearOnShutdown.formdata", true);
user_pref("privacy.clearOnShutdown.sessions", true);
EOF
)



create_user_js(){
  # Check profile directory
  if [[ ! -d "$PROFILE_BASE" ]]; then
    echo "❌ Error: Profile base not found: $PROFILE_BASE"
    echo "⏳ creating via headless launch: $PROFILE_BASE"
    flatpak run org.mozilla.firefox --headless --screenshot
    killall -u $USER firefox
    return 1
  else 
    # create a new profile
    echo "✅ $PROFILE_BASE FOUND"
  fi

  # Create user.js
  for folder in "$PROFILE_BASE"/*.default*; do
    # check profile folder
    [[ -d "$folder" ]] || continue
    
    if echo "$USER_JS_CONTENT" > "$folder/user.js"; then
      echo "✅ Created: $folder/user.js"
    else
      echo "❌ Failed: $folder/user.js"
    fi
  done
}

create_user_js


################
# remove old profiles
################


remove_old_profiles(){
  # Sort by mtime (newest first) via a tab-delimited find|sort|cut pipeline
  # instead of parsing `ls -t`, so folder names with spaces don't break.
  local sorted=()
  mapfile -t sorted < <(
    find "$PROFILE_BASE" -maxdepth 1 -type d -name '*.default-release*' \
      -printf '%T@\t%p\n' 2>/dev/null | sort -rn -t $'\t' -k1,1 | cut -f2-
  )
 
  # keep the newest, drop the rest
  local old_profile_folders=("${sorted[@]:1}")
 
  if [ "${#old_profile_folders[@]}" -gt 0 ]; then
    echo "🗑️ Remove the following folders:"
    printf '%s\n' "${old_profile_folders[@]}"
    rm -rf "${old_profile_folders[@]}"
  else
    echo "✅ No old profile to remove"
  fi
}
 
remove_old_profiles



###########
# policies
#########

POLICIES_PATH="$HOME/.local/share/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable/policies/policies.json"

POLICIES_CONTENT=$(cat << 'EOF'
{
  "policies": {
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      },
      "foxytab@eros.man": {
        "installation_mode": "blocked",
          "install_url": "https://addons.mozilla.org/ja/firefox/downloads/latest/foxytab/latest.xpi"
      }
    }
  }
}
EOF
)

create_policies(){
  if echo "$POLICIES_CONTENT" >  "$POLICIES_PATH"; then
    echo "✅ Created policies: $POLICIES_PATH"
  else
    echo "❌ Failed to Create policies: $POLICIES_PATH"
  fi
}

mkdir -p "$(dirname "$POLICIES_PATH")"
create_policies



