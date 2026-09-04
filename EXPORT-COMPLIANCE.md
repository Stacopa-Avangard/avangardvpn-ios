# Kepatuhan Ekspor — kenapa app ini menjawab YA

Hukum ekspor Amerika Serikat sampai hari ini masih memperlakukan enkripsi kuat
sebagai barang yang dikendalikan. App Store mengirim app ini dari server di AS,
yang membuat Apple berkedudukan sebagai eksportir, dan Apple menanyai setiap
pengembang tentang isi binernya sebelum dikirim keluar.

Deklarasi itu adalah **formulir bea cukai**, bukan pertanyaan teknis. Dokumen ini
memuat dasar jawaban kita, buktinya, dan satu kewajiban yang menyertainya.

> **Jawaban untuk AvangardVPN adalah YA — `usesNonExemptEncryption: true`.**
>
> Bukan karena VPN otomatis non-exempt, melainkan karena **app ini bersumber
> tertutup**. Fakta tunggal itulah yang memisahkan kita dari semua VPN WireGuard
> lain di App Store. Lihat [Kenapa Mullvad menjawab TIDAK](#kenapa-mullvad-ivpn-dan-wireguard-menjawab-tidak).

---

## Keadaan sekarang — PERLU TINDAKAN

Diperiksa lewat App Store Connect API pada **2026-09-04**:

| Resource | Tercatat | Seharusnya |
|---|---|---|
| Build `1.0 (2)` — `d6b97680-8754-467e-acc5-1a4a1a936590` | `usesNonExemptEncryption: false` | `true` |
| Build `1.0 (1)` — `35e71c63-99ff-4e5c-835e-704b7015bd46` | `usesNonExemptEncryption: false` | `true` |
| `appEncryptionDeclarations` (app `6808064676`) | `total: 0` | — |

Kedua build tercatat **exempt**, dan itu bertentangan dengan dokumen ini maupun
dengan [`project.yml`](project.yml) baris 191-245.

Nilai itu bukan berarti "belum dijawab": build yang belum menjawab berstatus
*Missing Compliance* dan tidak bisa didistribusikan sama sekali, sedangkan build
1 sudah sampai ke tester internal. Jadi pertanyaannya sudah dijawab — dan
dijawab keliru.

**Ini bukan bug plist.** Plist sudah benar dan sudah diverifikasi di arsip oleh
`387d49e1` ("app and extension both 1.0 (2), no ITS* keys, iPhone-only"). Nilai
yang salah hanya ada di App Store Connect.

### Cara memperbaikinya

Tanpa build ulang, tanpa unggah ulang, tanpa nomor build baru. Skema
`BuildUpdateRequest` milik Apple hanya membuka dua atribut yang boleh ditulis
pada sebuah build:

```
expired
usesNonExemptEncryption
```

Export compliance sengaja jadi salah satunya, karena jawabannya diberikan
*setelah* biner selesai dibangun dan bukan bagian dari biner itu. Satu panggilan
per build:

```
PATCH /v1/builds/<build-id>
{ "data": { "type": "builds", "id": "<build-id>",
            "attributes": { "usesNonExemptEncryption": true } } }
```

UI App Store Connect (TestFlight -> Builds -> iOS -> pilih build -> Export
Compliance) memanggil endpoint yang sama. UI sering menolak menyunting jawaban
yang sudah pernah diberikan; API tidak.

---

## Tiga pintu

Kebanyakan orang mengira pertanyaan ini punya dua jawaban. Sebenarnya tiga, dan
tertukarnya pintu pertama dengan pintu ketiga adalah sumber hampir semua
kesalahan.

Bayangkan bandara. Apple adalah pengangkutnya, app adalah barang kiriman, dan
pertanyaan tadi adalah petugas di gerbang.

### Pintu 1 — Jalur hijau: tidak ada yang perlu dideklarasikan

Setiap penumpang membawa ponsel, dan setiap ponsel berisi enkripsi. Tidak ada
yang mendeklarasikannya, karena itu melekat pada kendaraan, bukan pada muatan.

Dalam istilah app: satu-satunya kriptografi app adalah HTTPS lewat `URLSession`.
Dia **meminjam** kripto milik OS. Mayoritas app di App Store ada di sini.

### Pintu 2 — Jalur merah: saya mengangkut mesin sendiri

Di dalam peti ada mesin, dan mesin itu milik Anda, bukan milik pesawat.

Ini bukan pintu terlarang. Barangnya tetap lewat. Anda hanya mengisi formulir
supaya negara tahu apa yang keluar.

Dalam istilah app: app mengompilasi mesin kriptonya sendiri ke dalam biner.
**Di sinilah AvangardVPN berdiri.**

### Pintu 3 — Anda tidak pernah masuk aula bea cukai

Sekarang bayangkan cetak biru mesin itu sudah diterbitkan di perpustakaan umum.
Siapa pun, di mana pun, bisa membacanya dan membangun mesin yang sama, gratis.

Tidak ada lagi yang bisa dikendalikan. Pengetahuannya sudah keluar, dan menahan
satu peti tidak mengubah apa pun. Dalam bahasa regulasinya sendiri:

> Publicly available encryption source code **is not subject to the EAR**.

Perhatikan bedanya dengan Pintu 1:

| | |
|---|---|
| **Pintu 1** | Anda masuk aula, petugas melihat, lalu melambaikan tangan |
| **Pintu 3** | Anda **tidak pernah masuk aulanya**. Barangnya memang bukan urusan bea cukai |

---

## Di mana app ini berdiri, dan buktinya

Kripto itu terkompilasi ke dalam biner kita. Ditelusuri dari sumber, bukan
diasumsikan:

```
project.yml:111-114          paket WireGuardKit -> Stacopa-Avangard/wireguard-apple @ 65774b04
        |
project.yml:434-437          AvangardTunnel bergantung pada paket ITU dan pada target WireGuardGoBridge
        |
Scripts/build-wireguard-go.sh   menjalankan `make` di SourcePackages/checkouts/wireguard-apple/
                                Sources/WireGuardKitGo -> static library, ditautkan ke extension
        |
go.mod @ 65774b04            golang.zx2c4.com/wireguard + golang.org/x/crypto v0.6.0
                             (ChaCha20-Poly1305, Curve25519, BLAKE2s, Poly1305)
        |
Tunnel/Sources/PacketTunnelProvider.swift:17,43   import WireGuardKit; WireGuardAdapter(with: self)
```

`project.yml:440-441` sudah mengutip README WireGuardKit soal ini: *"WireGuardKit
links against wireguard-go-bridge"* — "Not optional, and not something a build
phase can replace."

Ada pula bukti runtime yang lebih kuat daripada pemeriksaan biner apa pun:
**tunnel terbukti bekerja di iPhone 12**, trafik sungguhan lewat `utun5`.
WireGuardKit tidak bisa berfungsi tanpa wireguard-go tertaut. Kalau kripto Go itu
tidak ada di dalam biner, tunnelnya tidak akan pernah naik.

### Satu-satunya tempat kita memakai kripto Apple

[`App/Sources/Core/WireGuardKey.swift`](App/Sources/Core/WireGuardKey.swift)
memakai `Curve25519.KeyAgreement` dari CryptoKit untuk membuat pasangan kunci.
Itu satu-satunya pemakaian kripto OS, dan cakupannya hanya pembuatan kunci —
tidak pernah jalur data tunnel.

Ini justru memperkuat, bukan melemahkan. Pengecualian yang biasa dijadikan
pegangan berbunyi "**limited to** encryption within the operating system".
Bahkan bagian app yang sebenarnya bisa sepenuhnya bersandar pada iOS pun tidak
mencakup jalur data — jadi tidak ada di sini yang *terbatas pada* kripto OS.

### Tidak satu pun pengecualian Apple berlaku

| Pengecualian yang ditawarkan | AvangardVPN |
|---|---|
| Khusus untuk penggunaan medis | tidak |
| Terbatas pada perlindungan kekayaan intelektual / DRM | tidak |
| Terbatas pada autentikasi, tanda tangan digital, atau dekripsi berkas | tidak — sign-in memakai token, tapi app tidak *terbatas* pada itu |
| Khusus perbankan atau transaksi uang | tidak |
| Fungsi kriptografi "tetap" (kartu pintar) | tidak |
| Panjang kunci simetris <= 56 bit | tidak — ChaCha20 itu 256 bit |
| Hanya tersedia di AS dan/atau Kanada | tidak — Indonesia |
| **Terbatas pada enkripsi bawaan sistem operasi** | **tidak** — wireguard-go membawa mesinnya sendiri |

Nol dari delapan. Pintu 1 tertutup. Pintu 3 tertutup karena repositori ini
privat. Tersisa Pintu 2, dan jawabannya YA.

---

## Kenapa Mullvad, IVPN dan WireGuard menjawab TIDAK

Setiap VPN WireGuard lain yang kami periksa mendeklarasikan sebaliknya. Plist
mereka, dibaca dari repositori publik masing-masing pada 2026-09-04:

| App | `ITSAppUsesNonExemptEncryption` | Lisensi | Repo |
|---|---|---|---|
| WireGuard resmi (app + extension) | `<false/>` | MIT | publik |
| Mullvad | `<false/>` | GPL-3.0 | publik |
| IVPN | `<false/>` | GPL-3.0 | publik |
| ProtonVPN | *kunci tidak ada* | — | dijawab di ASC, seperti kita |

Ketiga yang menjawab TIDAK adalah **app sumber terbuka penuh**. Mereka lewat
Pintu 3, dan jawaban mereka akurat.

Mesin di dalam peti mereka dan peti kita identik — sama-sama
`golang.org/x/crypto`. Cetak biru **mesin** itu memang publik di kedua kasus.

Tapi yang diuji bukan mesinnya, melainkan produk jadinya:

> object code is not subject to the EAR when the **corresponding source code**
> is also publicly available

Kode sumber produk jadi mereka publik. Milik kita tidak. Dua restoran bisa
memasak dari resep saus terbitan umum yang sama; yang satu menerbitkan seluruh
resep hidangannya, yang satu tidak.

**Meniru jawaban mereka berarti mengklaim pintu yang kuncinya tidak kita pegang.**

Perhatikan ProtonVPN: perusahaan VPN komersial besar yang tidak menaruh kunci itu
di plist sama sekali dan menjawabnya di App Store Connect — persis pola yang
diadopsi `76d8ee9` di sini.

---

## Apa yang dituntut oleh jawaban YA

Satu hal, dan sifatnya menengok ke belakang.

**Laporan self-classification tahunan** di bawah ECCN 5D002, License Exception
ENC 740.17(b)(1).

| | |
|---|---|
| Format | CSV — *"CSV format is the only format that will be accepted"* |
| Tenggat | **1 Februari**, mencakup ekspor sepanjang tahun kalender sebelumnya |
| Dikirim ke | `crypt-supp8@bis.doc.gov` dan `enc@nsa.gov` |
| Kolom (12) | PRODUCT NAME, MODEL NUMBER, MANUFACTURER, ECCN, AUTHORIZATION TYPE, ITEM TYPE, SUBMITTER NAME, TELEPHONE NUMBER, E-MAIL ADDRESS, MAILING ADDRESS, NON-U.S. COMPONENTS, NON-U.S. MANUFACTURING LOCATIONS |

Kalau app terdistribusi sepanjang 2026, laporan pertama jatuh tempo
**1 Februari 2027**. Tidak ada yang jatuh tempo di 2026.

Dua kelonggaran yang dikonfirmasi di halaman BIS sendiri:

> "No self-classification report is required if no exports or reexports of
> applicable items were made during the calendar year."

> "Each product appears only once — in the report for the year it was initially
> self-classified."

Jadi ini **bukan beban tahunan berulang per produk**. Produk didaftarkan sekali,
di tahun ia pertama kali diekspor. Tahun-tahun berikutnya cukup catatan satu
baris bahwa tidak ada perubahan, atau kirim ulang laporan yang sama.

### Yang tidak terutang

- **Tanpa ERN.** Kewajiban registrasi enkripsi sudah dihapus.
- **Tanpa CCATS.** Itu untuk algoritma proprietary. Semua primitif di sini ber-RFC
  IETF: ChaCha20-Poly1305 (8439), Curve25519 (7748), BLAKE2s (7693).
- **Tanpa lisensi, tanpa persetujuan di muka.** Tidak ada yang menahan rilis.
- **Tanpa deklarasi Prancis** selama app Indonesia-only.

> **Koreksi untuk [`project.yml`](project.yml):245** — di sana alamatnya ditulis
> `crypt@bis.doc.gov`. Menurut halaman BIS sendiri yang benar adalah
> **`crypt-supp8@bis.doc.gov`**. Laporan yang dikirim ke alamat salah sama dengan
> laporan yang tidak dikirim. Perbaiki komentarnya.

---

## Jebakan

**Nama fieldnya negatif ganda.** `usesNonExemptEncryption` berarti "memakai
enkripsi yang *tidak* dikecualikan".

| Nilai | Artinya | Pintu |
|---|---|---|
| `true` | kripto kita **tidak** dikecualikan | 2 |
| `false` | kripto kita **dikecualikan** | 1 |

**Layar ASC membaliknya.** UI bertanya *"Does your app qualify for any of the
exemptions?"* — mengklik **Yes** di situ menyimpan **`false`**. Kata "exemption"
terbaca seperti keringanan yang layak diambil, dan naluri orang mengambilnya.
Padahal ini pertanyaan faktual tentang isi peti, bukan tentang keuntungan. Inilah
penyebab paling mungkin dari nilai keliru di kedua build.

**Jangan kembalikan jawabannya ke plist.** `ITSAppUsesNonExemptEncryption: true`
di sana adalah klaim bahwa App Encryption Documentation sudah difile, dan Apple
lalu menuntut `ITSEncryptionExportComplianceCode` yang berpasangan. Unggahan gagal
dengan `ITMS-90592`. Itulah sebabnya `76d8ee9` mencabutnya, dan sebabnya
[`project.yml`](project.yml):191-245 menyatakan kunci itu sengaja tidak ada.
Jawabannya tempatnya di App Store Connect.

**Jangan menjawab YA pada pertanyaan lanjutan soal algoritma proprietary.**
Setelah mendeklarasikan non-exempt, ASC menanyakan apakah app
mengimplementasikan algoritma proprietary atau non-standar. Jawabannya **tidak**
— dan jawaban itulah yang menahan kita di baris "industry standard algorithm, not
provided within the Apple operating system", sekaligus menjauhkan dari proses
CCATS yang makan waktu berbulan-bulan.

---

## Yang bisa mengubah jawaban ini

Tiga pemicu. Salah satunya terjadi, dokumen ini jadi basi.

1. **Membuka repositori ini ke publik.** Kita pindah dari Pintu 2 ke Pintu 3,
   jawabannya menjadi `false`, dan laporan tahunan hilang seluruhnya — barangnya
   keluar dari cakupan EAR, bukan sekadar dimaafkan di dalamnya. Syaratnya: kode
   yang membangun biner yang dikirim harus publik (bukan sebagian), dan kodenya
   tidak dijual — menjual **layanan** VPN tetap boleh. Notifikasi TSU lama ke
   BIS/NSA sudah tidak diperlukan.

   Kalau ini dilakukan, struktur Mullvad adalah modelnya: kode sumber di bawah
   GPL-3.0, biner App Store di bawah EULA standar Apple. Lisensi ganda itu hanya
   bekerja karena satu entitas memegang seluruh hak cipta. **CLA wajib ada sejak
   kontribusi luar pertama** — begitu ada pihak lain ikut memiliki kodenya, kita
   tidak lagi bisa mendistribusikan biner di bawah syarat Apple secara sepihak,
   dan hak app untuk berada di App Store bergantung pada itu. VLC ditarik dari
   App Store pada 2011 persis karena hal ini.

2. **Membuka ketersediaan ke Prancis.** Deklarasi enkripsi Prancis jatuh tempo
   begitu app dijual di App Store Prancis.

3. **Menambahkan kriptografi non-standar.** Apa pun yang tidak ber-RFC memindahkan
   kita dari self-classification ke CCATS.

---

## Sumber

- [BIS — Annual Self-Classification](https://www.bis.gov/learn-support/encryption-controls/annual-self-classification)
- [BIS — Encryption items NOT subject to the EAR](https://www.bis.gov/learn-support/encryption-controls/encryption-items-not-subject-to-ear)
- [15 CFR 742.15 — Encryption items](https://www.law.cornell.edu/cfr/text/15/742.15)
- [Apple — Modify a Build (`BuildUpdateRequest`)](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-builds-_id_)
- [`project.yml`](project.yml):191-245 — kenapa kunci plist itu tidak ada
- `76d8ee9` — memindahkan deklarasi keluar dari plist
- `387d49e1` — arsip diverifikasi tidak membawa kunci `ITS*`

**Ini bukan nasihat hukum.** Satu titik memang belum tuntas: siapa yang dihitung
sebagai eksportir ketika perusahaan Indonesia mendistribusikan app Indonesia-only
lewat server Apple di AS. Praktiknya, pengembang memenuhi laporannya sendiri, dan
biayanya satu email setahun — jadi jalur amannya murah. Untuk kepastian penuh,
tanyakan ke konsultan trade compliance.
