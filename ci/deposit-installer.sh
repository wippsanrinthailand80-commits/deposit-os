#!/bin/bash
# ============================================================================
# Deposit OS disk installer — copies the running live system onto a target
# disk, installs GRUB, creates the user, and scrubs live-only state so the
# result boots as a normal installed OS.
#
# UI: whiptail (TUI). Launched from the "Install Deposit OS" desktop entry
# inside an xterm; also runnable from a console: sudo deposit-installer.
# Log: /var/log/deposit-install.log
# ============================================================================
set -euo pipefail

LOG=/var/log/deposit-install.log
exec > >(tee -a "$LOG") 2>&1

TITLE="Deposit OS Installer"
die() { whiptail --title "$TITLE" --msgbox "ERROR:\n$1" 14 74; exit 1; }

# --- 0. Privileges -----------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  exec sudo /usr/sbin/deposit-installer "$@"
fi

# --- 1. Welcome / destructive-action warning ---------------------------------
whiptail --title "$TITLE" --yesno \
"Welcome to Deposit OS.

This will INSTALL the running system onto a hard disk:
  * the TARGET DISK you choose will be COMPLETELY ERASED
  * a new user account will be created
  * GRUB will be installed so it boots on its own

Nothing is written until the final confirmation.
Continue?" 16 72 || exit 0

# --- 2. Pick the target disk ---------------------------------------------------
MEDIUM="$(findmnt -nro SOURCE /lib/live/mount/medium 2>/dev/null || true)"
MEDPARENT=""
if [ -n "$MEDIUM" ]; then
  _pk="$(lsblk -no PKNAME "$MEDIUM" 2>/dev/null | head -1 || true)"
  [ -n "$_pk" ] && MEDPARENT="/dev/$_pk"
fi

MENU=()
while read -r dev size model; do
  dev="$(readlink -f "$dev")"
  full="$dev"
  _pk="$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1 || true)"
  [ -n "$_pk" ] && full="/dev/$_pk"
  case "$full" in "$MEDIUM"|"$MEDPARENT") continue ;; esac   # never offer boot medium
  case "$full" in
    */loop*|*/ram*|*/sr*|*/fd*|*part*) continue ;;
    /dev/[shv]d[a-z]|/dev/nvme[0-9]n[0-9]|/dev/mmcblk[0-9]) ;;
    *) continue ;;
  esac
  MENU+=("$full" "$(printf '%-40s %s' "${model:-disk}" "$size")")
done < <(lsblk -dnpo NAME,SIZE,MODEL 2>/dev/null)

if [ ${#MENU[@]} -lt 2 ]; then
  die "No installable disk found.
(Only the boot medium is present.)"
fi

TARGET="$(whiptail --title "$TITLE" --menu \
"Choose the disk to install Deposit OS on.
EVERYTHING ON IT WILL BE DESTROYED." 18 78 6 "${MENU[@]}" 3>&1 1>&2 2>&3)" \
  || die "No disk selected."
DISK_INFO="$(lsblk -dn -o SIZE,MODEL "$TARGET" | tr '\n' ' ')"

whiptail --title "$TITLE" --yesno --defaultno \
"FINAL CHECK

Target disk : $TARGET ($DISK_INFO)
Action      : partition + format + install

All data on $TARGET will be lost forever.
Proceed?" 14 74 || exit 0

# --- 3. Collect identity before touching the disk ------------------------------
REGEX_USER='^[a-z_][a-z0-9_-]{0,30}$'
while :; do
  USERNAME="$(whiptail --title "$TITLE" --inputbox \
"Username for the new account
(lowercase letters, digits, -, _):" 11 70 "user" 3>&1 1>&2 2>&3)" || exit 0
  [[ "$USERNAME" =~ $REGEX_USER ]] && break
  whiptail --title "$TITLE" --msgbox "Invalid username: $USERNAME" 9 60
done
HOSTNAME="$(whiptail --title "$TITLE" --inputbox \
"Computer name (hostname):" 10 70 "deposit-pc" 3>&1 1>&2 2>&3)" || HOSTNAME="deposit-pc"
[[ "$HOSTNAME" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,61}$ ]] || HOSTNAME="deposit-pc"
while :; do
  PW1="$(whiptail --title "$TITLE" --passwordbox "Password for '$USERNAME':" 10 70 3>&1 1>&2 2>&3)" || exit 0
  PW2="$(whiptail --title "$TITLE" --passwordbox "Confirm password:" 10 70 3>&1 1>&2 2>&3)" || exit 0
  if [ -z "$PW1" ]; then
    whiptail --title "$TITLE" --msgbox "Password may not be empty." 8 60; continue
  fi
  [ "$PW1" = "$PW2" ] && break
  whiptail --title "$TITLE" --msgbox "Passwords do not match — try again." 8 60
done

# --- 4. Partition + format -------------------------------------------------------
echo "[installer] partitioning $TARGET ..."
swapoff -a 2>/dev/null || true
umount "${TARGET}"?* 2>/dev/null || true   # any mounted partitions of target
wipefs -a "$TARGET"

UEFI=no; [ -d /sys/firmware/efi ] && UEFI=yes
case "$TARGET" in
  *nvme*|*mmcblk*) P1="${TARGET}p1"; P2="${TARGET}p2" ;;
  *)               P1="${TARGET}1";  P2="${TARGET}2"  ;;
esac

if [ "$UEFI" = yes ]; then
  printf 'label:gpt\n,512M,U\n,,L,\n' | sfdisk "$TARGET" >/dev/null || die "partitioning failed (GPT)"
else
  printf 'label:dos\n,,83,*\n' | sfdisk "$TARGET" >/dev/null || die "partitioning failed (MBR)"
fi
partprobe "$TARGET" 2>/dev/null || true
sleep 1

echo "[installer] formatting ..."
if [ "$UEFI" = yes ]; then
  mkfs.vfat -F32 -n DEPOSIT_EFI "$P1" || die "mkfs.vfat failed"
fi
mkfs.ext4 -F -L deposit-root "$P2" || die "mkfs.ext4 failed"

ROOT_UUID="$(blkid -s UUID -o value "$P2")"
[ -n "$ROOT_UUID" ] || die "could not read root UUID"

# --- 5. Mount + copy the system ----------------------------------------------------
mkdir -p /mnt
mountpoint -q /mnt && umount -R /mnt 2>/dev/null || true
mount "$P2" /mnt || die "mounting root failed"
CLEANUP(){ umount -R /mnt/boot/efi 2>/dev/null || true; umount -R /mnt 2>/dev/null || true; }
trap CLEANUP EXIT

if [ "$UEFI" = yes ]; then
  mkdir -p /mnt/boot/efi
  mount "$P1" /mnt/boot/efi || die "mounting EFI partition failed"
fi

echo "[installer] copying system (this takes a while) ..."
rsync -aHAX --info=progress2 \
  --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' \
  --exclude='/tmp/*' --exclude='/mnt/*' --exclude='/media/*' --exclude='/lost+found' \
  --exclude='/var/cache/apt/archives/*.deb' --exclude='/lib/live/*' \
  / /mnt/ || die "rsync copy failed"

if ! ls /mnt/boot/vmlinuz-* >/dev/null 2>&1; then
  die "no kernel found in the copied system"
fi

# --- 6. Scrub live-only state --------------------------------------------------------
echo "[installer] removing live-session leftovers ..."
rm -f  /mnt/etc/lightdm/lightdm.conf.d/*autologin* 2>/dev/null || true
find /mnt/etc/systemd/system -name 'deposit-*' -type l -delete 2>/dev/null || true
rm -f  /mnt/etc/sudoers.d/50-deposit-live 2>/dev/null || true
rm -f  /mnt/etc/machine-id /mnt/var/lib/dbus/machine-id 2>/dev/null || true
rm -f  /mnt/etc/ssh/ssh_host_* 2>/dev/null || true
rm -f  /mnt/var/log/deposit-metrics-probe.log /mnt/var/log/deposit-web.log 2>/dev/null || true
mkdir -p /mnt/proc /mnt/sys /mnt/dev /mnt/run /mnt/tmp /mnt/media
chmod 1777 /mnt/tmp

# --- 7. fstab / identity ----------------------------------------------------------------
{
  echo "# generated by the Deposit OS installer"
  echo "UUID=$ROOT_UUID  /      ext4  errors=remount-ro  0 1"
  if [ "$UEFI" = yes ]; then
    ESP_UUID="$(blkid -s UUID -o value "$P1")"
    echo "UUID=$ESP_UUID  /boot/efi  vfat  umask=0077  0 2"
  fi
} > /mnt/etc/fstab

echo "$HOSTNAME" > /mnt/etc/hostname
sed -i "s/^127.0.1.1 .*/127.0.1.1 $HOSTNAME/" /mnt/etc/hosts 2>/dev/null || true
grep -qs "$HOSTNAME" /mnt/etc/hosts || echo "127.0.1.1 $HOSTNAME" >> /mnt/etc/hosts

# --- 8. User account ----------------------------------------------------------------------
for d in proc sys dev run; do
  mountpoint -q "/mnt/$d" || mount --bind "/$d" "/mnt/$d" 2>/dev/null || true
done
mountpoint -q /mnt/proc || mount -t proc proc /mnt/proc 2>/dev/null || true

in_chroot(){ chroot /mnt /bin/bash -lc "$*"; }

if in_chroot "id $USERNAME" >/dev/null 2>&1; then
  printf '%s:%s\n' "$USERNAME" "$PW1" | chroot /mnt chpasswd
else
  chroot /mnt useradd -m -s /bin/bash "$USERNAME"
  for g in sudo audio video plugdev netdev adm dialout cdrom; do
    chroot /mnt usermod -aG "$g" "$USERNAME" 2>/dev/null || true
  done
  printf '%s:%s\n' "$USERNAME" "$PW1" | chroot /mnt chpasswd
fi
chroot /mnt chage -d -1 "$USERNAME" 2>/dev/null || true   # normal login, no forced change

# --- 9. initramfs + bootloader ---------------------------------------------------------------
echo "[installer] initramfs ..."
in_chroot 'update-initramfs -u -k all' >/dev/null 2>&1 || true

echo "[installer] installing GRUB ..."
if [ "$UEFI" = yes ]; then
  in_chroot 'grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=DepositOS --removable --no-nvram' \
    || die "grub-install (EFI) failed"
else
  in_chroot "grub-install --target=i386-pc $TARGET" || die "grub-install (BIOS) failed"
fi
in_chroot 'update-grub' || die "update-grub failed"

for d in run dev sys proc; do umount -R "/mnt/$d" 2>/dev/null || true; done
trap - EXIT
CLEANUP

# --- 10. Done ----------------------------------------------------------------------------------
whiptail --title "$TITLE" --yesno \
"Installation complete!

Deposit OS is now installed on $TARGET.

Reboot into the new system now?" 12 66 && systemctl reboot
exit 0
