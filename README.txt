DAR-UL-SUKUN MAIN SYSTEM (Phase 1 - ek login, sab modules)
1. Is poore folder ko ek naye GitHub repo (jaise darulsukun-main) mein upload karen, Settings > Pages > main branch.
2. Login wahi users hain jo Supabase mein hain (supabase_setup.sql pehle run ho chuki ho).
3. Modules badalne/jorne ke liye index.html ke upar MODULES list mein url likhen.
4. dik/ folder = Donation in Kind (same login se khud khulta hai).
5. HR: office PC par HR-System.exe chalta rahe, Main System se "HR & Attendance" tile localhost:3000 kholti hai (sirf us PC par).
7. Admission online: admission_setup.sql bhi run karen. admission/ = Admission System (967 patients file ke andar, nayi entries/edits/photos/health Supabase mein sync hote hain).
   Purane browser mein jo nayi entries thin, pehle us purani file mein "Backup data" karen, phir yahan restore.
8. Store online: store_setup.sql run karen (table + 22 July ka data + live settings). store/ = Store app, ab Supabase par; login Main System se.
