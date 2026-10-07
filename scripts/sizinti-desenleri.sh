# Sızıntı desenleri — TEK KAYNAK (gelistir-kapisi.sh ve kancalar-kur.sh'nin pre-commit kancası `source` eder).
# Herkese açık depo: gerçek sızıntı biçimleri (uzun anahtar, e-posta, kişisel yol). `apiKey:` gibi kod parametre adları
# ve uydurma yollar (/Users/x, /Users/ornek) sayılmaz; uydurma e-posta alanları (@example.test, @ornek) desene girmez.
# Gerçek müşteri adı buraya YAZILMAZ (ad listesi depoya girer); ad denetimi kullanıcıdadır.
SIZINTI_DESEN='/Users/[a-z0-9._-]+|@gmail\.com|@icloud\.com|sk-ant-[A-Za-z0-9_-]{20,}|api[_-]?key *[:=] *"[A-Za-z0-9_-]{16,}"'
SAHTE_YOL='/Users/(x|ornek|ad|kullanici|sen)\b'
