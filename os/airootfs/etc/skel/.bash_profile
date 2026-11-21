# Sur tty1 : on lance directement la session console (aucun bureau).
if [ -z "$WAYLAND_DISPLAY" ] && [ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ]; then
  exec /usr/local/bin/hearth-session
fi
[ -f ~/.bashrc ] && . ~/.bashrc
