# คู่มือการใช้งาน Deposit OS (เวอร์ชัน 0.1.2)

**คู่มือฉบับสมบูรณ์** สำหรับ **Deposit OS** — ระบบปฏิบัติการ Linux ที่ออกแบบมาเพื่อความง่ายและรวดเร็ว 
พร้อมรองรับการติดตั้งแอปพลิเคชันจากทุกแพลตฟอร์ม: Ubuntu/Debian (.deb), Windows (.exe/.msi), 
Android (.apk), Alpine (.apk), Fedora/RHEL (.rpm), Arch (.pkg.tar.zst) 

---

## 📌 สารบัญ

1. [การติดตั้ง Deposit OS](#1-การติดตั้ง-deposit-os)
2. [การควบคุมระบบพื้นฐาน](#2-การควบคุมระบบพื้นฐาน)
3. [การติดตั้งแอปพลิเคชัน](#3-การติดตั้งแอปพลิเคชัน)
4. [Turbo Mode - โหมดเร่งความเร็ว](#4-turbo-mode---โหมดเร่งความเร็ว)
5. [Windows Mode - โหมด Windows](#5-windows-mode---โหมด-windows)
6. [การเชื่อมต่อเครือข่าย](#6-การเชื่อมต่อเครือข่าย)
7. [Settings - การปรับแต่งระบบ](#7-settings---การปรับแต่งระบบ)
8. [การอัปเดตระบบ](#8-การอัปเดตระบบ)
9. [Terminal - คำสั่งพื้นฐาน](#9-terminal---คำสั่งพื้นฐาน)
10. [การแก้ไขปัญหาเบื้องต้น](#10-การแก้ไขปัญหาเบื้องต้น)
11. [FAQ - คำถามที่พบบ่อย](#11-faq---คำถามที่พบบ่อย)
12. [ตารางสรุปคำสั่งสำคัญ](#12-ตารางสรุปคำสั่งสำคัญ)

---

## 1. 📥 การติดตั้ง Deposit OS

### 1.1 สร้าง USB Boot ได้
```bash
sudo dd if=deposit-os.iso of=/dev/sdX bs=4M status=progress; sync
```
> ⚠️ **ระวัง** แทนที่ `/dev/sdX` ด้วยไดรฟ์ USB ของคุณ (เช่น `/dev/sdb`) 
**ห้าม** ใช้ `/dev/sda` ถ้าเป็นไดรฟ์หลักของคุณ! อาจทำให้ข้อมูลสูญหาย

### 1.2 บูตจาก Live USB
กดปุ่มบูตเมนู (`F12`, `F9`, `Esc` ขึ้นอยู่กับเครื่อง) 
→ เลือก USB Boot 
→ รอระบบโหลด (Live Mode - ไม่ติดตั้ง)

### 1.3 ติดตั้งลงฮาร์ดดิสก์
- คลิกไอคอน **Install Deposit OS** บนเดสก์ท็อป
- เลือกไดรฟ์เป้าหมาย (**ระวัง:** ไม่สามารถเลือกไดรฟ์ที่กำลังรันอยู่)
- ยืนยันโดยพิมพ์ `yes` เพื่อเริ่มการติดตั้ง
- รอจนกว่าการติดตั้งเสร็จสิ้น → **รีบูต**
- ล็อกอินครั้งแรก: ระบบจะขอให้คุณตั้งรหัสผ่านใหม่

---

## 2. 🎯 การควบคุมระบบพื้นฐาน

| คำสั่ง/ฟังก์ชัน | แป้นลัด |
|---|---|
| Quick Menu (เมนูด่วน) | `Super+Q` (ปุ่ม Windows + Q) |
| เปิด Settings | `Super+S` หรือคลิกไอคอน Settings |
| Turbo Mode | `Super+T` |
| Windows Mode | `Super+W` |
| เปิด Terminal | `Ctrl+Alt+T` |
| Lock Screen | `Super+L` |
| Show Desktop | `Super+D` |
| Switch Window | `Alt+Tab` |
| Volume Up/Down | `F1/F2` หรือ `Fn+F1/F2` |
| Brightness Up/Down | `F5/F6` หรือ `Fn+F5/F6` |
| Wi-Fi Toggle | `Super+Q` → ไอคอน Wi-Fi |
| Airplane Mode | `Super+Q` → ไอคอน Airplane |

---

## 3. 📦 การติดตั้งแอปพลิเคชัน

### 3.1 แอปพลิเคชัน Ubuntu (.deb)
```bash
aqa install <URL>          # สแกน URL และติดตั้ง (รองรับทุกฟอร์แมต)
sudo apt install <ชื่อแพ็กเกจ>    # ติดตั้งผ่าน apt (Ubuntu)
```
> 💡 **หมายเหตุ:** `.deb` ต้องมี checksum SHA256 การติดตั้งจะล้มเหลวถ้าไม่มี

### 3.2 แอปพลิเคชัน Windows (.exe / .msi)
```bash
deposit-win setup.exe       # รันไฟล์ Windows (Wine, sandbox)
deposit-win --quiet app.msi # ติดตั้งโดยไม่แสดง dialog
deposit-winmode on          # เปิดโหมด Windows (Start Menu + Taskbar)
deposit-winmode off         # ปิดโหมด Windows
```

✅ **คุณสมบัติ:**
- รันใน **sandbox** (firejail/bubblewrap) ปลอดภัย
- ต้องได้รับการยืนยันก่อนรัน (SHA256 allowlist)
- ไม่วิ่งด้วยสิทธิ์ root **เด็ดขาด**

> ⚠️ **ถูกปฏิเสธ?** เพิ่ม hash ไฟล์ลงใน whitelist:
> ```bash
> echo <SHA256_HASH> >> ~/.config/deposit/win-hash-whitelist
> ```

### 3.3 แอปพลิเคชัน Android (.apk)
```bash
deposit-apk app.apk            # ติดตั้ง (auto-detect: Android/Alpine)
deposit-apk --android game.apk # บังคับให้ติดตั้งผ่าน Waydroid
deposit-apk --alpine pkg.apk   # บังคับให้ติดตั้งผ่าน apk-tools
```

📱 **สำหรับ Android:**
- ต้องเริ่มต้น Waydroid ก่อน: `sudo waydroid init`
- ถ้าเชื่อมต่อโทรศัพท์: แอปจะถูกติดตั้งผ่าน `adb install`

🐧 **สำหรับ Alpine:**
- ติดตั้งใน prefix: `~/.deposit/alpine`
- รันแอป: `deposit-apk run <ชื่อแอป>`
- ดูรายการ: `deposit-apk list`

### 3.4 แพ็กเกจ Fedora/RHEL (.rpm) และ Arch (.pkg.tar.zst)
```bash
deposit-pkg app.rpm              # แตกไฟล์ไปยัง ~/.deposit/rpm
deposit-pkg program.pkg.tar.zst  # แตกไฟล์ไปยัง ~/.deposit/arch
deposit-pkg run rpm <คำสั่ง>       # รันภายใน sandbox
deposit-pkg list                # ดูรายการแพ็กเกจที่ติดตั้ง
```

⚠️ **ข้อจำกัด:**
- **ไม่** แก้ dependency อัตโนมัติ (ต้องติดตั้ง dependency ด้วยตัวเอง)
- รันใน **bubblewrap sandbox** เท่านั้น
- SHA256 allowlist: ต้อง whitelist ก่อน

---

## 4. ⚡ Turbo Mode - โหมดเร่งความเร็ว

```
  +---------------------+
  |   TURBO MODE 🚀     |
  +---------------------+
  | 🚀 CPU: Maximum      |
  | ⚡ GPU: Performance  |
  | ⏳ Duration: 30 min  |
  | 🎨 FX: Spinning Fade |
  +---------------------+
  | Press Super+T       |
  +---------------------+
```

**การใช้งาน:**
- กด `Super+T` เพื่อ **เปิด** Turbo Mode
- กดอีกครั้งเพื่อ **ปิด**

✨ **คุณสมบัติ:**
- CPU: เปลี่ยนเป็น **performance governor** (ความเร็วสูงสุด)
- GPU: เปลี่ยนเป็น **maximum performance mode**
- มีเอฟเฟกต์ **spinning/fade transition** ขณะสลับ
- **เวลา:** ปกติ 30 นาที (ปรับแต่งได้)

📊 **สถานะ:**
- ไอคอน Turbo จะแสดงสถานะปัจจุบันใน Quick Menu (`Super+Q`)
- สี: ✅ เขียว = เปิด, ❌ แดง = ปิด

> 💡 **Tip:** เหมาะสำหรับการเรนเดอร์วิดีโอ, เล่นเกม, หรืองานที่ต้องการความเร็วสูง

---

## 5. 🪟 Windows Mode - โหมด Windows

```
  +-------------------------+
  |    WINDOWS MODE 🪟     |
  +-------------------------+
  | 🖥️  Taskbar Style       |
  | 🎯 Start Button          |
  | 🎨 Breeze-Dark Theme     |
  | 📁 Windows-like UI       |
  +-------------------------+
  | Press Super+W           |
  +-------------------------+
```

**การใช้งาน:**
```bash
deposit-winmode on          # เปิดโหมด Windows
deposit-winmode off         # ปิดโหมด Windows
deposit-winmode toggle      # สลับโหมด
```

✨ **คุณสมบัติ:**
- **Taskbar** แบบ Windows พร้อม **Start Button**
- **Theme:** Breeze-Dark (คล้าย Windows)
- **Font:** Carlito (คล้าย Calibri)
- **Cursor:** Breeze cursors
- **Widget:** GTK widgets เปลี่ยนเป็นสไตล์ Windows

🎯 **การติดตั้งแอป Windows:**
1. ดาวน์โหลดไฟล์ `.exe` หรือ `.msi`
2. คลิกขวา → **Open With** → **Deposit Win Installer**
3. หรือใช้คำสั่ง: `deposit-win <ไฟล์.exe>`
4. ยืนยันการติดตั้ง (SHA256 verification)

> ⚠️ **ความปลอดภัย:**
> - แอปจะรันใน **sandbox** (firejail/bubblewrap)
> - ไม่มีสิทธิ์ root
> - ต้อง whitelist hash ก่อน (ดูหน้า 3.2)

🔄 **Switch ระหว่างโหมด:**
- `Super+W` → สลับระหว่าง Deposit Panel กับ Windows Taskbar
- สามารถสลับได้ทุกเมื่อ **ไม่ต้องรีบูต**

---

## 6. 🌐 การเชื่อมต่อเครือข่าย

### 6.1 Wi-Fi

```
  +---------------------+
  |   Wi-Fi 📶         |
  +---------------------+
  | 🔍 Search Networks   |
  | 🔒 Password Input    |
  | ✅ Connected        |
  +---------------------+
```

**การเชื่อมต่อ:**
1. กด `Super+Q` → เปิด Quick Menu
2. คลิกไอคอน **Wi-Fi**
3. เลือกเครือข่าย → ใส่รหัสผ่าน → เชื่อมต่อ

🔧 **Troubleshooting:**
```bash
# เปิด Wi-Fi (ถ้าไม่ทำงาน)
rfkill unblock wifi
rfkill unblock all

# รีสตาร์ท network manager
sudo systemctl restart NetworkManager

# เช็กสถานะ
nmcli device status
ip a
```

### 6.2 Bluetooth

```
  +---------------------+
  |  Bluetooth 🔵      |
  +---------------------+
  | 🎧 Headphones        |
  | 🖱️  Mouse            |
  | 📱  Phone            |
  | ✅ A2DP Support      |
  +---------------------+
```

**การเชื่อมต่อ:**
1. กด `Super+Q` → เปิด Quick Menu
2. คลิกไอคอน **Bluetooth**
3. เปิด Bluetooth → ค้นหาอุปกรณ์ → เชื่อมต่อ

✅ **คุณสมบัติพิเศษ:**
- **A2DP Profile** สำหรับเสียงคุณภาพสูง (AirPods, Galaxy Buds, etc.)
- รองรับการเชื่อมต่อหลายอุปกรณ์พร้อมกัน

🔧 **Troubleshooting:**
```bash
# เปิด Bluetooth
rfkill unblock bluetooth

# รีสตาร์ท service
sudo systemctl restart bluetooth

# เช็กสถานะ
bluetoothctl status
```

### 6.3 Ethernet (LAN)
- เชื่อมสาย LAN → เชื่อมต่ออัตโนมัติ
- เช็กสถานะ: คลิกไอคอนเครือข่ายใน Quick Menu

---

## 7. ⚙️ Settings - การปรับแต่งระบบ

```
  +-------------------------+
  |      SETTINGS ⚙️        |
  +-------------------------+
  | 🖥️  Display             |
  | 🔊 Sound               |
  | 🌐 Network             |
  | 🔒 Security            |
  | 🔋 Power               |
  | 🌍 Language            |
  | 🎨 Appearance          |
  | 📱 Bluetooth           |
  | ✈️ Airplane Mode       |
  | 🚀 Turbo               |
  | 🪟 Windows Mode        |
  +-------------------------+
```

**การเปิด Settings:**
- กด `Super+S`
- หรือคลิกไอคอน **Settings** ใน Quick Menu (`Super+Q`)

### 7.1 Display
- **Resolution:** ปรับความละเอียดหน้าจอ
- **Refresh Rate:** เลือกอัตรารีฟเรช
- **Night Light:** ลดแสงสีฟ้าในตอนกลางคืน
- **Compositor:** เปิด/ปิดเอฟเฟกต์ภาพ (เปิดโดยค่าเริ่มต้น)

### 7.2 Sound
- **Volume:** ปรับระดับเสียง
- **Output Device:** เลือกอุปกรณ์ออกเสียง
- **Input Device:** เลือกไมโครโฟน
- **Bluetooth Audio:** เชื่อมต่อหูฟัง Bluetooth

### 7.3 Network
- **Wi-Fi:** เชื่อมต่อ/ตัดการเชื่อมต่อ
- **Ethernet:** ตั้งค่า IP คงที่
- **VPN:** ตั้งค่า VPN
- **Proxy:** ตั้งค่าพรอกซี

### 7.4 Security
```
  +---------------------+
  |   SECURITY 🔒       |
  +---------------------+
  | 🛡️  Firewall (ufw)  |
  | 🦠  ClamAV           |
  | 🔐 AppArmor         |
  | 📋 Hash Whitelist   |
  +---------------------+
```

- **Firewall (ufw):** เปิด/ปิด และตั้งค่ากฎ
  ```bash
  sudo ufw enable       # เปิด firewall
  sudo ufw disable      # ปิด firewall
  sudo ufw status       # เช็กสถานะ
  ```

- **ClamAV (Antivirus):**
  ```bash
  deposit-av scan       # สแกนไฟล์
  deposit-av update     # อัปเดตฐานข้อมูล
  ```

- **AppArmor:** ปกป้องระบบด้วยนโยบายความปลอดภัย

### 7.5 Power
- **Sleep:** เวลาก่อนเข้าสู่โหมด Sleep
- **Suspend:** เวลาก่อน Suspend
- **Lid Close:** กำหนดการกระทำเมื่อปิดฝา
- **Turbo Mode:** ตั้งค่าการใช้งาน Turbo

### 7.6 Language
- **Thai (th_TH):** ตั้งเป็นค่าเริ่มต้น
- **Input Method:** IBus (กด `Super+Space` สลับภาษา)
- **Keyboard Layout:** US, TH, etc.

### 7.7 Appearance
- **Theme:** Andromeda ( theme หลัก)
- **Icons:** Papirus-Dark
- **Cursor:** Breeze
- **Wallpaper:** Sagittarius A* (ภาพหลุมดำ)

### 7.8 Special Features
- **Turbo Mode:** เปิด/ปิด และตั้งค่าระยะเวลา
- **Windows Mode:** สลับโหมด UI
- **Quick Menu:** ปรับแต่งไอคอน

---

## 8. 🔄 การอัปเดตระบบ

```
  +---------------------+
  |   UPDATES 🔄       |
  +---------------------+
  | 📦 System (apt)     |
  | 📦 Deposit (.mlpds) |
  | 🍷 Wine             |
  | 🤖 Waydroid         |
  | 📱 Alpine           |
  +---------------------+
```

### 8.1 อัปเดตระบบ (apt)
```bash
# อัปเดตรายการแพ็กเกจ
sudo apt update

# อัปเกรดแพ็กเกจ
sudo apt upgrade

# อัปเกรดเต็มรูปแบบ
sudo apt full-upgrade

# ลบแพ็กเกจที่ไม่จำเป็น
sudo apt autoremove
```

### 8.2 อัปเดต Deposit Apps (.mlpds)
```bash
# อัปเดต registry
aqa update

# อัปเกรดแพ็กเกจที่ติดตั้ง
sudo aqa upgrade
```

### 8.3 อัปเดต Runtimes
- **Wine:**
  ```bash
  sudo apt update wine
  ```

- **Waydroid:**
  ```bash
  sudo waydroid init --update
  ```

- **Alpine Prefix:**
  ```bash
  deposit-apk update
  ```

### 8.4 Deposit Updater (GUI)
1. เปิด **Settings** → **Updates**
2. คลิก **Check for Updates**
3. เลือกแพ็กเกจที่ต้องการอัปเดต
4. คลิก **Install Updates**

✅ **คุณสมบัติ:**
- แสดง changelog สำหรับแต่ละแพ็กเกจ
- มี progress bar แสดงความคืบหน้า
- **ไม่** รีบูตอัตโนมัติ (ให้คุณตัดสินใจ)

---

## 9. 💻 Terminal - คำสั่งพื้นฐาน

### 9.1 คำสั่งระบบ

```bash
# เช็กเวอร์ชัน Deposit OS
cat /etc/deposit-version

# เช็กอุณหภูมิ CPU
sensors

# เช็กการใช้งาน CPU
htop

# เช็กการใช้งานแรม
free -h

# เช็กพื้นที่ดิสก์
df -h

# เช็กการเชื่อมต่อเครือข่าย
ping google.com

# เช็ก IP Address
ip a

# เช็กการใช้งาน GPU (NVIDIA)
nvidia-smi
```

### 9.2 คำสั่งการจัดการไฟล์

```bash
# ดูไฟล์ในไดเรกทอรี
ls

# ดูไฟล์พร้อมรายละเอียด
ls -la

# สร้างไดเรกทอรี
mkdir <ชื่อโฟลเดอร์>

# ลบไฟล์
rm <ชื่อไฟล์>

# ลบโฟลเดอร์ (วมไฟล์ภายใน)
rm -rf <ชื่อโฟลเดอร์>

# คัดลอกไฟล์
cp <ต้นทาง> <ปลายทาง>

# ย้าย/เปลี่ยนชื่อไฟล์
mv <ชื่อเดิม> <ชื่อใหม่>

# ดูเนื้อหาไฟล์
cat <ชื่อไฟล์>

# ดูเนื้อหาไฟล์ทีละหน้า
less <ชื่อไฟล์>
```

### 9.3 คำสั่งการจัดการแพ็กเกจ

```bash
# ค้นหาแพ็กเกจ
apt search <คำค้นหา>

# ติดตั้งแพ็กเกจ
sudo apt install <ชื่อแพ็กเกจ>

# ลบแพ็กเกจ
sudo apt remove <ชื่อแพ็กเกจ>

# ลบแพ็กเกจพร้อมคอนฟิก
sudo apt purge <ชื่อแพ็กเกจ>

# ค้นหาไฟล์ในแพ็กเกจ
dpkg -L <ชื่อแพ็กเกจ>

# เช็กว่าแพ็กเกจติดตั้งอยู่หรือไม่
which <ชื่อโปรแกรม>
```

### 9.4 คำสั่งเครือข่าย

```bash
# ดาวน์โหลดไฟล์
wget <URL>

# ดาวน์โหลดไฟล์ (รองรับ resume)
curl -O <URL>

# อัปโหลด/ดาวน์โหลดไฟล์
scp <ไฟล์> <user>@<host>:<path>

# เชื่อมต่อ SSH
ssh <user>@<host>

# โอนย้ายไฟล์ผ่าน SSH
rsync -avz <source> <user>@<host>:<destination>
```

### 9.5 คำสั่ง Deposit OS เฉพาะ

```bash
# เช็กความเข้ากันได้ของไฟล์
Deposit-compat check <ไฟล์>

# เช็กสถานะ Turbo Mode
deposit-turbo status

# เช็กสถานะ Windows Mode
deposit-winmode status

# สแกนไวรัส
deposit-av scan

# เช็กการอัปเดต
deposit-updater check
```

---

## 10. 🔧 การแก้ไขปัญหาเบื้องต้น

### 10.1 Wi-Fi ไม่เชื่อมต่อ

**อาการ:**
- ไม่เห็นเครือข่าย Wi-Fi
- เชื่อมต่อล้มเหลว
- Wi-Fi ปิดใช้งาน

**วิธีแก้:**
```bash
# 1. เช็กว่า Wi-Fi ถูกบล็อกหรือไม่
rfkill list

# 2. เปิด Wi-Fi
rfkill unblock wifi
rfkill unblock all

# 3. รีสตาร์ท NetworkManager
sudo systemctl restart NetworkManager

# 4. เช็กอุปกรณ์ Wi-Fi
lspci | grep -i network
ip a

# 5. ติดตั้งไดรเวอร์ (ถ้าจำเป็น)
sudo apt install firmware-<brand>
```

### 10.2 เสียงไม่ออก

**อาการ:**
- ไม่มีเสียง
- เสียงเบา
- เสียงกระตุก

**วิธีแก้:**
```bash
# 1. เช็กอุปกรณ์เสียง
aplay -l

# 2. เช็ก volume
alsamixer

# 3. รีสตาร์ท PulseAudio
pulseaudio -k && pulseaudio --start

# 4. เปลี่ยน output device
pavucontrol
```

### 10.3 Bluetooth ไม่เชื่อมต่อ

**อาการ:**
- ไม่เห็นอุปกรณ์ Bluetooth
- เชื่อมต่อล้มเหลว
- เสียงไม่ออกจากหูฟัง Bluetooth

**วิธีแก้:**
```bash
# 1. เช็กว่า Bluetooth ถูกบล็อกหรือไม่
rfkill list

# 2. เปิด Bluetooth
rfkill unblock bluetooth

# 3. รีสตาร์ท bluetooth service
sudo systemctl restart bluetooth

# 4. เช็กสถานะ
bluetoothctl status

# 5. สแกนอุปกรณ์
bluetoothctl scan on
bluetoothctl devices
```

### 10.4 Turbo Mode ไม่ทำงาน

**อาการ:**
- กด `Super+T` แล้วไม่เกิดอะไรขึ้น
- CPU/GPU ยังคงอยู่ในโหมดปกติ

**วิธีแก้:**
```bash
# 1. เช็กสถานะ
Deposit-turbo status

# 2. เริ่ม Turbo Mode ด้วยมือ
deposit-turbo on

# 3. เช็กว่า service ทำงานหรือไม่
sudo systemctl status deposit-turbo

# 4. รีสตาร์ท service
sudo systemctl restart deposit-turbo
```

### 10.5 Windows Mode ไม่ทำงาน

**อาการ:**
- กด `Super+W` แล้วไม่เกิดอะไรขึ้น
- Taskbar ไม่เปลี่ยน

**วิธีแก้:**
```bash
# 1. เช็กสถานะ
Deposit-winmode status

# 2. สลับโหมดด้วยมือ
deposit-winmode toggle

# 3. ติดตั้ง Wine (ถ้ายังไม่ติดตั้ง)
sudo apt install wine

# 4. รีสตาร์ท XFCE
deposit-winmode restart
```

### 10.6 แอปพลิเคชัน Windows ไม่รัน

**อาการ:**
- ไฟล์ .exe ไม่เปิด
- ข้อความ "REFUSED"
- Error ขณะรัน

**วิธีแก้:**
```bash
# 1. เพิ่ม hash ลงใน whitelist
echo <SHA256_HASH> >> ~/.config/deposit/win-hash-whitelist

# 2. รันด้วย --no-sandbox (ไม่แนะนำ)
deposit-win --no-sandbox setup.exe

# 3. เช็กว่า Wine ติดตั้งหรือไม่
which wine

# 4. ติดตั้ง Wine (ถ้ายังไม่ติดตั้ง)
sudo apt install wine winetricks
```

### 10.7 ระบบค้าง

**อาการ:**
- ระบบไม่ตอบสนอง
- เมาส์/คีย์บอร์ดไม่ทำงาน
- หน้าจอค้าง

**วิธีแก้:**
```bash
# 1. ลองเปิด Terminal (Ctrl+Alt+T)
# 2. รีสตาร์ท XFCE
xfce4-panel -r

# 3. รีสตาร์ท LightDM (login screen)
sudo systemctl restart lightdm

# 4. รีบูต (ถ้าไม่มีทางเลือก)
reboot
```

### 10.8 การติดตั้งล้มเหลว

**อาการ:**
- ไม่สามารถติดตั้ง Deposit OS ได้
- Error ขณะติดตั้ง

**วิธีแก้:**
- เช็กว่า USB Boot ได้หรือไม่
- ลองใช้ USB อื่น
- ลองใช้โปรแกรมเขียน USB อื่น (Rufus, Balena Etcher)
- เช็ก checksum ของไฟล์ ISO

---

## 11. ❓ FAQ - คำถามที่พบบ่อย

### ❔ Deposit OS คืออะไร?
**✅** Deposit OS เป็นระบบปฏิบัติการ Linux ที่ออกแบบมาเพื่อความง่ายและรวดเร็ว 
พร้อมรองรับการติดตั้งแอปพลิเคชันจากทุกแพลตฟอร์ม โดยใช้ kernel ของตัวเอง (Linux 6.6.58) 
และ userspace ที่เข้ากันได้กับ Ubuntu/Debian

### ❔ Deposit OS ใช้งานได้กับฮาร์ดแวร์อะไรบ้าง?
**✅** รองรับ:
- **x86_64 (amd64):** คอมพิวเตอร์ส่วนใหญ่ (Intel, AMD)
- **ARM64:** Raspberry Pi 4/5, Snapdragon X (ในอนาคต)
- **Minimum:** RAM 1 GB, Storage 8 GB
- **Recommended:** RAM 2 GB+, Storage 16 GB+

### ❔ ติดตั้งแอป Windows ได้ยังไง?
**✅** ใช้คำสั่ง `deposit-win` หรือคลิกขวาที่ไฟล์ .exe/.msi 
→ เลือก **Open With** → **Deposit Win Installer**
แอปจะรันใน sandbox (Wine) พร้อมการปกป้องความปลอดภัย

### ❔ Turbo Mode ทำงานยังไง?
**✅** Turbo Mode จะ:
- เปลี่ยน CPU governor เป็น **performance** (ความเร็วสูงสุด)
- เปลี่ยน GPU เป็น **maximum performance mode**
- มีเอฟเฟกต์ transition สวยงาม
- คุณสามารถปิดได้โดยกด `Super+T` อีกครั้ง

### ❔ Windows Mode แตกต่างจากปกติยังไง?
**✅** Windows Mode จะ:
- เปลี่ยน UI เป็นสไตล์ Windows (Taskbar + Start Button)
- ใช้ Theme Breeze-Dark (คล้าย Windows)
- ใช้ Font Carlito (คล้าย Calibri)
- เปลี่ยน Widget เป็นสไตล์ Windows
- **ไม่** ต้องรีบูต เพียงกด `Super+W`

### ❔ Deposit OS ปลอดภัยแค่ไหน?
**✅** Deposit OS มี:
- **AppArmor:** ปกป้องระบบด้วยนโยบายความปลอดภัย
- **ClamAV:** โปรแกรมป้องกันไวรัส
- **ufw:** Firewall
- **Sandbox:** แอป Windows/Alpine/RPM/Arch รันใน sandbox
- **SHA256 Allowlist:** ต้อง whitelist hash ก่อนรันไฟล์
- **GPG Verification:** .mlpds packages ถูกตรวจสอบด้วย GPG

### ❔ จะอัปเดตระบบยังไง?
**✅** มี 2 วิธี:
1. **GUI:** Settings → Updates → Check for Updates
2. **Terminal:** 
   ```bash
   sudo apt update && sudo apt upgrade
   aqa update && sudo aqa upgrade
   ```

### ❔ ใช้งาน Bluetooth ได้ยังไง?
**✅** 
1. กด `Super+Q` → เปิด Quick Menu
2. คลิกไอคอน **Bluetooth**
3. เปิด Bluetooth → ค้นหาอุปกรณ์ → เชื่อมต่อ

**สำหรับเสียงคุณภาพสูง:** Deposit OS รองรับ **A2DP Profile** 
เพื่อให้ AirPods, Galaxy Buds และหูฟัง Bluetooth อื่นๆ ทำงานได้ดี

### ❔ ใช้งาน Thai Input ยังไง?
**✅** 
- กด `Super+Space` เพื่อสลับภาษา
- ใช้ IBus เป็น input method
- Font Thai (fonts-thai-tlwg) ติดตั้งมาให้พร้อม

### ❔ Deposit OS ใช้งานกับ NVIDIA GPU ได้ไหม?
**✅** Yes! Deposit OS มี **NVIDIA Beta Channel**:
- Kernel modules (open source) ถูก compile กับ kernel 6.6.58
- Userspace จาก Ubuntu 24.04
- ติดตั้งผ่าน: `aqa install nvidia-driver-beta.mlpds`
- **รองรับ:** Turing (GTX 16xx) และใหม่กว่า

### ❔ ARM64 รองรับอะไรบ้าง?
**✅** ปัจจุบัน:
- QEMU virt machine (ทดสอบใน CI)
- Raspberry Pi 4/5 (UEFI)
- **อนาคต:** Snapdragon X laptops

### ❔ จะติดตั้งแอปจาก Android ได้ยังไง?
**✅** ใช้คำสั่ง:
```bash
deposit-apk app.apk
```
- ถ้า Waydroid ทำงานอยู่: แอปจะถูกติดตั้งใน container
- ถ้าไม่มี: แอปจะถูกส่งไปยังโทรศัพท์ผ่าน ADB

### ❔ ใช้งาน .rpm และ .pkg.tar.zst ได้ยังไง?
**✅** ใช้คำสั่ง:
```bash
deposit-pkg app.rpm            # แตกไฟล์ไปยัง ~/.deposit/rpm
deposit-pkg program.pkg.tar.zst # แตกไฟล์ไปยัง ~/.deposit/arch
deposit-pkg run rpm <คำสั่ง>    # รันภายใน sandbox
```
- **ข้อจำกัด:** ไม่แก้ dependency อัตโนมัติ
- รันใน bubblewrap sandbox

### ❔ จะลบ Deposit OS ออกได้ยังไง?
**✅** 
1. Backup ข้อมูลสำคัญ
2. ใช้ USB Boot ของระบบปฏิบัติการอื่น (Windows, Ubuntu, etc.)
3. ลบพาร์ทิชัน Deposit OS
4. ขยายพาร์ทิชันหลัก (ถ้าจำเป็น)

### ❔ Deposit OS ใช้พื้นที่ดิสก์เท่าไหร่?
**✅** 
- **ISO:** ~1.7 GB
- **Installed System:** ~1.4 GB (rootfs + kernel + Firefox + Wine + Thai fonts)
- **ARM64 Image:** ~840-870 MB

---

## 12. 📋 ตารางสรุปคำสั่งสำคัญ

### 📥 การติดตั้ง

| คำสั่ง | คำอธิบาย |
|---|---|
| `aqa install <URL>` | ติดตั้งจาก URL (รองรับทุกฟอร์แมต) |
| `sudo apt install <pkg>` | ติดตั้งแพ็กเกจ Ubuntu |
| `deposit-win <file.exe>` | ติดตั้งแอป Windows |
| `deposit-apk <file.apk>` | ติดตั้งแอป Android/Alpine |
| `deposit-pkg <file.rpm>` | แตกไฟล์ RPM |

### 🔧 การจัดการระบบ

| คำสั่ง | คำอธิบาย |
|---|---|
| `Super+Q` | เปิด Quick Menu |
| `Super+T` | สลับ Turbo Mode |
| `Super+W` | สลับ Windows Mode |
| `Super+S` | เปิด Settings |
| `Ctrl+Alt+T` | เปิด Terminal |
| `Super+L` | ล็อกหน้าจอ |

### 🌐 เครือข่าย

| คำสั่ง | คำอธิบาย |
|---|---|
| `rfkill unblock wifi` | เปิด Wi-Fi |
| `rfkill unblock bluetooth` | เปิด Bluetooth |
| `sudo systemctl restart NetworkManager` | รีสตาร์ทเครือข่าย |
| `ping google.com` | ทดสอบการเชื่อมต่อ |
| `ip a` | เช็ก IP Address |

### 🔄 การอัปเดต

| คำสั่ง | คำอธิบาย |
|---|---|
| `sudo apt update` | อัปเดตรายการแพ็กเกจ |
| `sudo apt upgrade` | อัปเกรดแพ็กเกจ |
| `aqa update` | อัปเดต AQA registry |
| `sudo aqa upgrade` | อัปเกรดแพ็กเกจ AQA |

### 🛡️ ความปลอดภัย

| คำสั่ง | คำอธิบาย |
|---|---|
| `sudo ufw enable` | เปิด Firewall |
| `sudo ufw disable` | ปิด Firewall |
| `deposit-av scan` | สแกนไวรัส |
| `echo <hash> >> ~/.config/deposit/win-hash-whitelist` | เพิ่ม whitelist |

### 🔍 การตรวจสอบ

| คำสั่ง | คำอธิบาย |
|---|---|
| `htop` | เช็กการใช้งาน CPU/RAM |
| `df -h` | เช็กพื้นที่ดิสก์ |
| `sensors` | เช็กอุณหภูมิ |
| `nvidia-smi` | เช็ก GPU (NVIDIA) |
| `deposit-turbo status` | เช็ก Turbo Mode |

### 💻 การจัดการไฟล์

| คำสั่ง | คำอธิบาย |
|---|---|
| `ls` | ดูไฟล์ในไดเรกทอรี |
| `ls -la` | ดูไฟล์พร้อมรายละเอียด |
| `mkdir <folder>` | สร้างโฟลเดอร์ |
| `rm <file>` | ลบไฟล์ |
| `rm -rf <folder>` | ลบโฟลเดอร์ |
| `cp <src> <dest>` | คัดลอกไฟล์ |
| `mv <old> <new>` | ย้าย/เปลี่ยนชื่อไฟล์ |

---

## 📜 ข้อมูลเพิ่มเติม

- **เว็บไซต์:** [Deposit OS GitHub](https://github.com/wippsanrinthailand80-commits/deposit-os)
- **License:** GPL-3.0
- **เวอร์ชัน:** 0.1.2 (Beta)
- **Kernel:** Linux 6.6.58 LTS
- **Userspace:** Ubuntu 24.04 (Noble)

---

## 🙏 ขอบคุณ

ขอบคุณที่ใช้งาน **Deposit OS** 
เราหวังว่าคู่มือนี้จะช่วยให้คุณใช้งานระบบได้อย่างมีประสิทธิภาพ

**หากพบปัญหา:**
- เช็กในส่วน [Troubleshooting](#10-การแก้ไขปัญหาเบื้องต้น)
- อ่าน [FAQ](#11-faq---คำถามที่พบบ่อย)
- เปิด Issue บน GitHub

---

*Deposit OS Beta 0.1.2 — พัฒนาโดยทีม Deposit OS (GPL-3.0)*
*Last Updated: 2024*
