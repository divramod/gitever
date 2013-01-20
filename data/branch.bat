::datenbank erstellen
cd\
c:
cd xampp\mysql\bin\

::Datenbank befüllen
::===============================================
::mysql -u d01420ed -pd01420ed %version_new% < c:/xampp/htdocs/au/branches/%version_new%/install/sql/functions.sql
mysql -u d01420ed -pge ge < c:/code/pro/gitever/data/functions.sql
mysql -u d01420ed -pge ge < c:/code/pro/gitever/data/structure_and_data_dump_d01420ed_20130119_2128.sql
::mysql -u d01420ed -pd01420ed %version_new% < c:/xampp/htdocs/au/branches/%version_new%/install/sql/productive.sql

pause