SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES latin1 */;

DROP FUNCTION IF EXISTS `get_aufgeteilter_betrag_for_er`;
DELIMITER $$
--
-- Funktionen
--
CREATE FUNCTION `get_aufgeteilter_betrag_for_er`(id_rechnung INT, betrag_rechnung DECIMAL(10,2)) RETURNS char(100) CHARSET latin1
BEGIN
	DECLARE done INT DEFAULT FALSE;

	DECLARE id_ks INT;
	
	DECLARE summe_skonti DECIMAL(20,2);
	DECLARE ks_gesamtbezug DECIMAL(20,2);
	
	
	DECLARE prozent_kswert_aufgeteilt DECIMAL(20,2);
	DECLARE summe_individueller_betrag DECIMAL(20,2);
	DECLARE summe_kswertvorlage_betrag DECIMAL(20,2);
	DECLARE summe_kswertvorlage_gesamtbezug DECIMAL(20,2);
	
	-- = summe_individueller_betrag + summe_kswertvorlage_betrag
	DECLARE summe_aufgeteilter_betrag CHAR(200);

	-- helper
	DECLARE loop_helper DECIMAL(20,2);
	DECLARE loop_helper_1 DECIMAL(20,2);
	DECLARE loop_counter INT;

	-- cursor
	DECLARE cur_kostenschluessel CURSOR FOR 
		SELECT 
			kswertvorlage.fk_id_ks,
			get_ks_gesamtbezug(kswertvorlage.fk_id_ks) AS gesamtbezug
		FROM 
			kswert LEFT JOIN kswertvorlage ON kswert.fk_id_kswertvorlage = kswertvorlage.id
		WHERE
			kswert.fk_id_rechnung = id_rechnung AND
			kswert.fk_id_kswertvorlage IS NOT NULL
		GROUP BY
			kswertvorlage.fk_id_ks
		ORDER BY
			kswertvorlage.fk_id_ks DESC
	;
	-- helper cursor end
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
	
	-- 1. Skonti zur Rechnung berechnen
	SET summe_skonti := 0;
	SET summe_skonti := (
		SELECT
			SUM(
				rechnungzahlung.skonto
			)
		FROM
			rechnungzahlung
		WHERE
			rechnungzahlung.fk_id_rechnung = id_rechnung
	);
	
	-- 2. aufgeteilterBetrag individuell
	SET summe_individueller_betrag := 0;
	SET summe_individueller_betrag := IFNULL((
		SELECT
			SUM(
				(
					betrag_rechnung
					-
					summe_skonti
				)
				*
				kswert.prozent
				/
				100
			)
		FROM
			kswert
		WHERE
			kswert.fk_id_rechnung = id_rechnung AND
			kswert.fk_id_kswertvorlage IS NULL
	),0);
	
	
	
-- 3. aufgeteilterBetrag mit fk_id_kswertvorlage existent
-- Loop durch die einzelnen genutzten Kostenschlüssel
	
	-- Set helper
	SET loop_helper := 0;
	SET loop_helper_1 := 0;
	SET loop_counter := 0;
	
	SET ks_gesamtbezug := 0;
	SET summe_kswertvorlage_betrag := "";
	SET summe_kswertvorlage_gesamtbezug := "";
	
	
	-- Schleife Anfang
	OPEN cur_kostenschluessel;

	read_loop: LOOP
		-- FETCH
		FETCH cur_kostenschluessel INTO id_ks, ks_gesamtbezug;
		
		-- LEAVE
		IF done THEN
			LEAVE read_loop;
		END IF;
		
		-- Block mit Loop Counter
		SET prozent_kswert_aufgeteilt := (
			SELECT
				kswert.prozent
			FROM
				kswert LEFT JOIN kswertvorlage ON kswert.fk_id_kswertvorlage = kswertvorlage.id
			WHERE
				kswertvorlage.fk_id_ks = id_ks
			GROUP BY
				kswertvorlage.fk_id_ks
		);
		
		-- Berechnet den verteilten betrag für einen gewählten ks
		SET loop_helper := 
		(
			
			(
				prozent_kswert_aufgeteilt 
				* 
				(
					SELECT
						SUM(
							(
								betrag_rechnung
								-
								summe_skonti
							)
							*
							kswert.prozent
							/
							100
							*
							kswertvorlage.wert
							/
							ks_gesamtbezug
						) AS aufgeteilterBetrag
					FROM
						kswert LEFT JOIN kswertvorlage ON kswert.fk_id_kswertvorlage = kswertvorlage.id
					WHERE
						kswertvorlage.fk_id_ks = id_ks AND
						kswert.fk_id_rechnung = id_rechnung
				)
				/
				100
			)
		);
		
		SET loop_helper_1 := summe_kswertvorlage_betrag;
		SET summe_kswertvorlage_betrag := (loop_helper_1 + loop_helper);
		
		
		-- LOOP COUNTER
		SET loop_counter := loop_counter + 1;
	END LOOP;

	CLOSE cur_kostenschluessel;
  -- Schleife Ende
  
	-- Berechnung gesamter verteilter Betrag
	SET summe_aufgeteilter_betrag := (summe_kswertvorlage_betrag + summe_individueller_betrag);
	
	RETURN summe_aufgeteilter_betrag;
END$$
DELIMITER ;

DROP FUNCTION IF EXISTS `get_ks_gesamtbezug`;
DELIMITER $$
CREATE FUNCTION `get_ks_gesamtbezug`(id_ks INT) RETURNS decimal(20,2)
BEGIN
	DECLARE ks_gesamtbezug DECIMAL(20,2);
	SET ks_gesamtbezug := (
		SELECT
			SUM(
				kswertvorlage.wert
			)
		FROM
			kswertvorlage
		WHERE
			kswertvorlage.fk_id_ks = id_ks
	);
	
	RETURN ks_gesamtbezug;
END$$
DELIMITER ;

DROP FUNCTION IF EXISTS `get_ks_namen_for_rechnung`;
DELIMITER $$
CREATE FUNCTION `get_ks_namen_for_rechnung`(id_rechnung INT) RETURNS char(200) CHARSET latin1
BEGIN
	-- loop helper
	DECLARE loop_counter INT;
	DECLARE done INT DEFAULT FALSE;
	
	-- inhalt helper
	DECLARE loop_helper CHAR(200);
	DECLARE ks_name_string CHAR(200);
	DECLARE ksname_loop CHAR(200);
	
	-- cursor
	DECLARE cur_kswert CURSOR FOR 
		SELECT
			CONCAT(ks.ksnummer, " - ", ks.ksname)
		FROM 
			(kswert LEFT JOIN kswertvorlage ON kswert.fk_id_kswertvorlage = kswertvorlage.id)
				LEFT JOIN ks ON kswertvorlage.fk_id_ks = ks.id
		WHERE
			kswert.fk_id_rechnung = id_rechnung AND
			kswert.fk_id_kswertvorlage IS NOT NULL
		GROUP BY
			kswertvorlage.fk_id_ks
		ORDER BY
			kswertvorlage.fk_id_ks
	;
	-- helper cursor end
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
	
-- Loop durch die einzelnen genutzten Kostenschlüssel
	
	-- Set helper
	SET loop_helper := "";
	SET loop_counter := 0;
	SET ks_name_string := "";
	SET ksname_loop := "";
	
	-- Schleife Anfang
	OPEN cur_kswert;

	read_loop: LOOP
		-- FETCH
		FETCH cur_kswert INTO ksname_loop;
		
		-- LEAVE
		IF done THEN
			LEAVE read_loop;
		END IF;
		
		IF loop_counter > 0 THEN
			SET loop_helper := CONCAT(ks_name_string, "; ");
		ELSE
			SET loop_helper := ks_name_string;
		END IF;
		
		
		SET ks_name_string := CONCAT(loop_helper, ksname_loop);
		
		-- LOOP COUNTER
		SET loop_counter := loop_counter + 1;
	END LOOP;

	CLOSE cur_kswert;
  -- Schleife Ende
	
	RETURN ks_name_string;
END$$
DELIMITER ;

DROP FUNCTION IF EXISTS `get_personen_for_wohneinheit`;
DELIMITER $$
CREATE FUNCTION `get_personen_for_wohneinheit`(id_wohneinheit INT) RETURNS char(100) CHARSET latin1
BEGIN
  DECLARE done INT DEFAULT FALSE;
  
  DECLARE id_eigentuemergruppe INT;
  DECLARE name CHAR(100);
  DECLARE result_name CHAR(200);
  DECLARE loop_helper CHAR(200);
  DECLARE loop_counter INT;
  
  DECLARE cur1 CURSOR FOR 
	SELECT 
		eigentuemergruppe.id,
		concat(
			trim(`person`.`nachname`),
			', ',
			trim(`person`.`vorname`)
		) AS name
	FROM 
		(((
		eigentuemergruppe 
		join 
			eigentuemergruppehatperson on eigentuemergruppe.id = eigentuemergruppehatperson.fk_id_eigentuemergruppe)
		join
			person on person.id = eigentuemergruppehatperson.fk_id_person)
		join
			wohneinheit on wohneinheit.fk_id_eigentuemergruppe = eigentuemergruppe.id)
	WHERE
		wohneinheit.id = id_wohneinheit
	;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  SET loop_helper := "";
  SET result_name := "";
  SET loop_counter := 0;
  
  OPEN cur1;

  read_loop: LOOP
    FETCH cur1 INTO id_eigentuemergruppe, name;
    IF done THEN
      LEAVE read_loop;
    END IF;
	IF loop_counter = 0 THEN
		SET result_name := CONCAT (loop_helper, name);
		SET loop_helper := result_name;
	ELSE
		SET result_name := CONCAT (loop_helper, "; ", name);
		SET loop_helper := result_name;
	END IF;
	SET loop_counter := loop_counter + 1;
  END LOOP;

  CLOSE cur1;
  
  RETURN result_name;
END$$
DELIMITER ;

DROP FUNCTION IF EXISTS `get_personen_for_wohneinheit2`;
DELIMITER $$
CREATE FUNCTION `get_personen_for_wohneinheit2`(id_wohneinheit INT) RETURNS char(100) CHARSET latin1
BEGIN
  DECLARE done INT DEFAULT FALSE;
  
  DECLARE id_eigentuemergruppe INT;
  DECLARE name CHAR(100);
  DECLARE result_name CHAR(200);
  DECLARE loop_helper CHAR(200);
  DECLARE loop_counter INT;
  
  DECLARE cur1 CURSOR FOR 
	SELECT 
		eigentuemergruppe.id,
		concat(
			trim(`person`.`nachname`),
			', ',
			trim(`person`.`vorname`)
		) AS name
	FROM 
		((
		eigentuemergruppe 
		join 
			eigentuemergruppehatperson on eigentuemergruppe.id = eigentuemergruppehatperson.fk_id_eigentuemergruppe)
		join
			person on person.id = eigentuemergruppehatperson.fk_id_person)
	WHERE
		eigentuemergruppe.id = id_wohneinheit
	;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  SET loop_helper := "";
  SET result_name := "";
  SET loop_counter := 0;
  
  OPEN cur1;

  read_loop: LOOP
    FETCH cur1 INTO id_eigentuemergruppe, name;
    IF done THEN
      LEAVE read_loop;
    END IF;
	IF loop_counter = 0 THEN
		SET result_name := CONCAT (loop_helper, name);
		SET loop_helper := result_name;
	ELSE
		SET result_name := CONCAT (loop_helper, "; ", name);
		SET loop_helper := result_name;
	END IF;
	SET loop_counter := loop_counter + 1;
  END LOOP;

  CLOSE cur1;
  
  RETURN result_name;
END$$
DELIMITER ;

DROP FUNCTION IF EXISTS `get_personen_for_wohneinheit_1`;
DELIMITER $$
CREATE FUNCTION `get_personen_for_wohneinheit_1`(id_wohneinheit INT) RETURNS char(100) CHARSET latin1
BEGIN
  DECLARE done INT DEFAULT FALSE;
  
  DECLARE id_eigentuemergruppe INT;
  DECLARE name CHAR(100);
  DECLARE result_name CHAR(200);
  DECLARE loop_helper CHAR(200);
  DECLARE loop_counter INT;
  
  DECLARE cur1 CURSOR FOR 
	SELECT 
		eigentuemergruppe.id,
		concat(
			trim(`person`.`nachname`),
			', ',
			trim(`person`.`vorname`)
		) AS name
	FROM 
		((
		eigentuemergruppe 
		join 
			eigentuemergruppehatperson on eigentuemergruppe.id = eigentuemergruppehatperson.fk_id_eigentuemergruppe)
		join
			person on person.id = eigentuemergruppehatperson.fk_id_person)
	WHERE
		eigentuemergruppe.id = id_wohneinheit
	;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  SET loop_helper := "";
  SET result_name := "";
  SET loop_counter := 0;
  
  OPEN cur1;

  read_loop: LOOP
    FETCH cur1 INTO id_eigentuemergruppe, name;
    IF done THEN
      LEAVE read_loop;
    END IF;
	IF loop_counter = 0 THEN
		SET result_name := CONCAT (loop_helper, name);
		SET loop_helper := result_name;
	ELSE
		SET result_name := CONCAT (loop_helper, "; ", name);
		SET loop_helper := result_name;
	END IF;
	SET loop_counter := loop_counter + 1;
  END LOOP;

  CLOSE cur1;
  
  RETURN result_name;
END$$
DELIMITER ;

DROP FUNCTION IF EXISTS get_aufgeteilter_betrag_for_er_and_we;
DELIMITER $$
CREATE FUNCTION get_aufgeteilter_betrag_for_er_and_we(id_rechnung INT, id_wohneinheit INT, betrag_rechnung DECIMAL(10,2)) RETURNS char(100) CHARSET latin1
BEGIN
	DECLARE done INT DEFAULT FALSE;

	DECLARE id_ks INT;
	
	DECLARE summe_skonti DECIMAL(20,2);
	DECLARE ks_gesamtbezug DECIMAL(20,2);
	
	
	DECLARE prozent_kswert_aufgeteilt DECIMAL(20,2);
	DECLARE summe_individueller_betrag DECIMAL(20,2);
	DECLARE summe_kswertvorlage_betrag DECIMAL(20,2);
	DECLARE summe_kswertvorlage_gesamtbezug DECIMAL(20,2);
	
	-- = summe_individueller_betrag + summe_kswertvorlage_betrag
	DECLARE summe_aufgeteilter_betrag CHAR(200);

	-- helper
	DECLARE loop_helper DECIMAL(20,2);
	DECLARE loop_helper_1 DECIMAL(20,2);
	DECLARE loop_counter INT;

	-- cursor
	DECLARE cur_kostenschluessel CURSOR FOR 
		SELECT 
			kswertvorlage.fk_id_ks,
			get_ks_gesamtbezug(kswertvorlage.fk_id_ks) AS gesamtbezug
		FROM 
			kswert LEFT JOIN kswertvorlage ON kswert.fk_id_kswertvorlage = kswertvorlage.id
		WHERE
			kswert.fk_id_rechnung = id_rechnung AND
			kswert.fk_id_kswertvorlage IS NOT NULL AND
			kswert.fk_id_wohneinheit = id_wohneinheit
		GROUP BY
			kswertvorlage.fk_id_ks
		ORDER BY
			kswertvorlage.fk_id_ks DESC
	;
	-- helper cursor end
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
	
	-- 1. Skonti zur Rechnung berechnen
	SET summe_skonti := 0;
	SET summe_skonti := (
		SELECT
			SUM(
				rechnungzahlung.skonto
			)
		FROM
			rechnungzahlung
		WHERE
			rechnungzahlung.fk_id_rechnung = id_rechnung
	);
	
	-- 2. aufgeteilterBetrag individuell
	SET summe_individueller_betrag := 0;
	SET summe_individueller_betrag := IFNULL((
		SELECT
			SUM(
				(
					betrag_rechnung
					-
					summe_skonti
				)
				*
				kswert.prozent
				/
				100
			)
		FROM
			kswert
		WHERE
			kswert.fk_id_rechnung = id_rechnung AND
			kswert.fk_id_kswertvorlage IS NULL AND
			kswert.fk_id_wohneinheit = id_wohneinheit
	),0);
	
	
	
-- 3. aufgeteilterBetrag mit fk_id_kswertvorlage existent
-- Loop durch die einzelnen genutzten Kostenschlüssel
	
	-- Set helper
	SET loop_helper := 0;
	SET loop_helper_1 := 0;
	SET loop_counter := 0;
	
	SET ks_gesamtbezug := 0;
	SET summe_kswertvorlage_betrag := 0;
	SET summe_kswertvorlage_gesamtbezug := "";
	
	
	-- Schleife Anfang
	OPEN cur_kostenschluessel;

	read_loop: LOOP
		-- FETCH
		FETCH cur_kostenschluessel INTO id_ks, ks_gesamtbezug;
		
		-- LEAVE
		IF done THEN
			LEAVE read_loop;
		END IF;
		
		-- Block mit Loop Counter
		SET prozent_kswert_aufgeteilt := (
			SELECT
				kswert.prozent
			FROM
				kswert LEFT JOIN kswertvorlage ON kswert.fk_id_kswertvorlage = kswertvorlage.id
			WHERE
				kswertvorlage.fk_id_ks = id_ks AND 
				kswert.fk_id_wohneinheit = id_wohneinheit
			GROUP BY
				kswertvorlage.fk_id_ks
		);
		
		-- Berechnet den verteilten betrag für einen gewählten ks
		SET loop_helper := 
		(
			SELECT
				(
					prozent_kswert_aufgeteilt 
					/
					100
					*
					(
						betrag_rechnung
						-
						summe_skonti
					)
					*
					kswertvorlage.wert
					/
					ks_gesamtbezug
				) AS aufgeteilterBetrag
			FROM
				kswert LEFT JOIN kswertvorlage ON kswert.fk_id_kswertvorlage = kswertvorlage.id
			WHERE
				kswertvorlage.fk_id_ks = id_ks AND
				kswert.fk_id_rechnung = id_rechnung AND
				kswert.fk_id_wohneinheit = id_wohneinheit
		);
		
		SET loop_helper_1 := summe_kswertvorlage_betrag;
		SET summe_kswertvorlage_betrag := (loop_helper_1 + loop_helper);
		
		
		-- LOOP COUNTER
		SET loop_counter := loop_counter + 1;
	END LOOP;

	CLOSE cur_kostenschluessel;
  -- Schleife Ende
  
	-- Berechnung gesamter verteilter Betrag
	SET summe_aufgeteilter_betrag := (summe_kswertvorlage_betrag + summe_individueller_betrag);
	
	RETURN summe_aufgeteilter_betrag;
END$$

DELIMITER ;

####################################################################################################
# get_rechnungzahlung_sum_skonto(id_rechnung INT)
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnungzahlung_sum_skonto`;

DELIMITER $$

CREATE FUNCTION `get_rechnungzahlung_sum_skonto`(id_rechnung INT) RETURNS char(100) CHARSET latin1
BEGIN  
	-- cursor
	DECLARE sum_skonto DECIMAL(20,14);
	
	SET sum_skonto := 
	IFNULL
	(
		(
			SELECT
				SUM(rechnungzahlung.skonto)
			FROM
				rechnungzahlung
			WHERE
				rechnungzahlung.fk_id_rechnung = id_rechnung
		),
		0
	);
	
  RETURN sum_skonto;
END$$

DELIMITER ;

####################################################################################################
# get_rechnungzahlung_sum_skonto_date(id_rechnung INT, startdate DATE, enddate DATE)
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnungzahlung_sum_skonto_date`;

DELIMITER $$

CREATE FUNCTION `get_rechnungzahlung_sum_skonto_date`(id_rechnung INT, startdate DATE, enddate DATE) RETURNS char(100) CHARSET latin1
BEGIN  
	-- cursor
	DECLARE sum_skonto DECIMAL(20,14);
	
	SET sum_skonto := 
	IFNULL
	(
		(
			SELECT
				SUM(rechnungzahlung.skonto)
			FROM
				rechnungzahlung
			WHERE
				rechnungzahlung.fk_id_rechnung = id_rechnung AND
				rechnungzahlung.zahldatum BETWEEN startdate AND enddate
		),
		0
	);
	
	RETURN sum_skonto;
END$$

DELIMITER ;

####################################################################################################
# get_rechnungzahlung_sum_zahlbetrag(id_rechnung INT)
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnungzahlung_sum_zahlbetrag`;

DELIMITER $$

CREATE FUNCTION `get_rechnungzahlung_sum_zahlbetrag`(id_rechnung INT) RETURNS char(100) CHARSET latin1
BEGIN  
	-- cursor
	DECLARE sum_skonto DECIMAL(20,14);
	
	SET sum_skonto := 
	IFNULL
	(
		(
			SELECT
				SUM(rechnungzahlung.zahlbetrag)
			FROM
				rechnungzahlung
			WHERE
				rechnungzahlung.fk_id_rechnung = id_rechnung
		),
		0
	);
	
  RETURN sum_skonto;
END$$

DELIMITER ;

####################################################################################################
# get_rechnungzahlung_sum_zahlbetrag_date(id_rechnung INT, startdate DATE, enddate DATE)
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnungzahlung_sum_zahlbetrag_date`;

DELIMITER $$

CREATE FUNCTION `get_rechnungzahlung_sum_zahlbetrag_date`(id_rechnung INT, startdate DATE, enddate DATE) RETURNS char(100) CHARSET latin1
BEGIN  
	-- cursor
	DECLARE sum_skonto DECIMAL(20,14);
	
	SET sum_skonto := 
	IFNULL
	(
		(
			SELECT
				SUM(rechnungzahlung.zahlbetrag)
			FROM
				rechnungzahlung
			WHERE
				rechnungzahlung.fk_id_rechnung = id_rechnung AND
				rechnungzahlung.zahldatum BETWEEN startdate AND enddate
		),
		0
	);
	
	RETURN sum_skonto;
END$$

DELIMITER ;

####################################################################################################
# WE INDIVIDUELL: get_rechnung_verteilung_we_prozent_individuell(id_rechnung INT, id_wohneinheit INT)
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnung_verteilung_we_prozent_individuell`;

DELIMITER $$

CREATE FUNCTION `get_rechnung_verteilung_we_prozent_individuell`(id_rechnung INT, id_wohneinheit INT) RETURNS char(100) CHARSET latin1
BEGIN  
	DECLARE percent DECIMAL(20,14);
	
	SET percent := 
	(
		IFNULL
		(
			(
				SELECT
					SUM(k.prozent)
				FROM
					kswert AS k
				WHERE
					k.fk_id_rechnung = id_rechnung AND
					k.fk_id_wohneinheit = id_wohneinheit AND
					k.fk_id_kswertvorlage IS NULL
			),
			0
		)
		/
		100
	);
	
	RETURN percent;
END$$

DELIMITER ;

####################################################################################################
# WE KS: get_rechnung_verteilung_we_prozent_ks(id_rechnung INT, id_wohneinheit INT)
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnung_verteilung_we_prozent_ks`;

DELIMITER $$

CREATE FUNCTION `get_rechnung_verteilung_we_prozent_ks`(id_rechnung INT, id_wohneinheit INT) RETURNS char(100) CHARSET latin1
BEGIN  
	DECLARE percent DECIMAL(20,14);	
	
	-- cursor
	SET percent := 
	IFNULL
	(
		(
			SELECT 
				SUM(kswertvorlage.wert/get_ks_gesamtbezug(kswertvorlage.fk_id_ks)*kswert.prozent/100) AS prozent
			FROM 
				kswert LEFT JOIN kswertvorlage ON kswert.fk_id_kswertvorlage = kswertvorlage.id
			WHERE
				kswert.fk_id_rechnung = id_rechnung AND
				kswert.fk_id_wohneinheit = id_wohneinheit AND
				kswert.fk_id_kswertvorlage IS NOT NULL
		),
		0
	);

	RETURN percent;
END$$

DELIMITER ;

####################################################################################################
# WE GESAMT: get_rechnung_verteilung_we_prozent_gesamt(id_rechnung INT, id_wohneinheit INT)
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnung_verteilung_we_prozent_gesamt1`;

DELIMITER $$

CREATE FUNCTION `get_rechnung_verteilung_we_prozent_gesamt`(id_rechnung INT, id_wohneinheit INT) RETURNS char(100) CHARSET latin1
BEGIN  
	DECLARE percent DECIMAL(20,14);
	SET percent := 
	IFNULL
	(
		(
			get_rechnung_verteilung_we_prozent_ks(id_rechnung, id_wohneinheit) + get_rechnung_verteilung_we_prozent_individuell(id_rechnung, id_wohneinheit)
		),
		0
	);
	RETURN percent;
END$$

DELIMITER ;

####################################################################################################
# WE GESAMT: get_rechnung_verteilung_we_prozent_gesamt1(id_rechnung INT, id_wohneinheit INT)
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnung_verteilung_we_prozent_gesamt1`;

DELIMITER $$

CREATE FUNCTION `get_rechnung_verteilung_we_prozent_gesamt1`(id_rechnung INT, id_wohneinheit INT) RETURNS char(100) CHARSET latin1
BEGIN  
	DECLARE percent DECIMAL(20,14);
	
	SET percent := 
	(
		IFNULL
		(
			(
				SELECT
					SUM(k.faktor)
				FROM
					kswert AS k
				WHERE
					k.fk_id_rechnung = id_rechnung AND
					k.fk_id_wohneinheit = id_wohneinheit
			),
			0
		)
		/
		100
	);
	
	RETURN percent;
END$$

DELIMITER ;

####################################################################################################
# OG INDIVIDUELL: get_rechnung_verteilung_og_prozent_individuell(id_rechnung INT)
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnung_verteilung_og_prozent_individuell`;

DELIMITER $$

CREATE FUNCTION `get_rechnung_verteilung_og_prozent_individuell`(id_rechnung INT) RETURNS char(100) CHARSET latin1
BEGIN  
	DECLARE percent DECIMAL(20,14);
	
	SET percent := 
	(
		IFNULL
		(
			(
				SELECT
					SUM(k.prozent)
				FROM
					kswert AS k
				WHERE
					k.fk_id_rechnung = id_rechnung AND
					k.fk_id_kswertvorlage IS NULL
			),
			0
		)
		/
		100
	);
	
	RETURN percent;
END$$

DELIMITER ;

####################################################################################################
# OG KS: get_rechnung_verteilung_og_prozent_ks(id_rechnung INT)
# Summe ProzentJeKs / ZähleDsJeKs als möglichkeit --> performance testen
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnung_verteilung_og_prozent_ks`;

DELIMITER $$

CREATE FUNCTION `get_rechnung_verteilung_og_prozent_ks`(id_rechnung INT) RETURNS char(100) CHARSET latin1
BEGIN  
	DECLARE percent DECIMAL(20,14);	
	
	-- cursor
	SET percent := 
	IFNULL
	(
		(
			SELECT 
				SUM(kswertvorlage.wert/get_ks_gesamtbezug(kswertvorlage.fk_id_ks)*kswert.prozent/100) AS prozent
			FROM 
				kswert LEFT JOIN kswertvorlage ON kswert.fk_id_kswertvorlage = kswertvorlage.id
			WHERE
				kswert.fk_id_rechnung = id_rechnung AND
				kswert.fk_id_kswertvorlage IS NOT NULL
		),
		0
	);

	RETURN percent;
END$$

DELIMITER ;

####################################################################################################
# OG GESAMT: get_rechnung_verteilung_og_prozent_gesamt(id_rechnung INT)
####################################################################################################
DROP FUNCTION IF EXISTS `get_rechnung_verteilung_og_prozent_gesamt`;

DELIMITER $$

CREATE FUNCTION `get_rechnung_verteilung_og_prozent_gesamt`(id_rechnung INT) RETURNS char(100) CHARSET latin1
BEGIN  
	DECLARE percent DECIMAL(20,14);
	SET percent := 
	IFNULL
	(
		(
			get_rechnung_verteilung_og_prozent_ks(id_rechnung) + get_rechnung_verteilung_og_prozent_individuell(id_rechnung)
		),
		0
	);
	RETURN percent;
END$$

DELIMITER ;

####################################################################################################
# rechnung_get_first_rechnungzahlungsdatum(id_rechnung INT)
####################################################################################################
DROP FUNCTION IF EXISTS `rechnung_get_first_rechnungzahlungsdatum`;

DELIMITER $$

CREATE FUNCTION `rechnung_get_first_rechnungzahlungsdatum`(id_rechnung INT) RETURNS CHAR(50) CHARSET latin1
BEGIN	
	RETURN (
		SELECT 
			zahldatum
		FROM 
			rechnungzahlung
		WHERE
			fk_id_rechnung = id_rechnung
		ORDER BY
			zahldatum ASC
		LIMIT 0, 1
	);
END$$

DELIMITER ;

####################################################################################################
# ez_wejeog_gesamt(id_wohneinheit INT, id_og INT)
####################################################################################################
DROP FUNCTION IF EXISTS `ez_wejeog_gesamt`;

DELIMITER $$

CREATE FUNCTION ez_wejeog_gesamt(id_wohneinheit INT, id_og INT, startdate DATE, enddate DATE) RETURNS CHAR(50) CHARSET latin1
BEGIN	
	RETURN (
		IFNULL(
			(
				SELECT 
					SUM(betrag)
				FROM 
					eigentuemerzahlung AS e LEFT JOIN konto AS k ON (e.fk_id_konto = k.id)
				WHERE
					e.fk_id_wohneinheit = id_wohneinheit
					AND k.fk_id_og = id_og
					AND datum BETWEEN startdate AND enddate			
			),
			0
		)
	);
END$$

DELIMITER ;

####################################################################################################
# wohneinheit_get_verteilter_betrag_kostengruppe_1(id_wohneinheit INT, id_kostengruppe INT, id_og INT, startdate DATE, enddate DATE)
####################################################################################################
DROP FUNCTION IF EXISTS `wohneinheit_get_verteilter_betrag_kostengruppe_1`;

DELIMITER $$

CREATE FUNCTION wohneinheit_get_verteilter_betrag_kostengruppe_1(id_wohneinheit INT, id_og INT, id_kostengruppe INT, startdate DATE, enddate DATE) RETURNS CHAR(50) CHARSET latin1
BEGIN	
	RETURN (
		IFNULL(
			(
				SELECT
					SUM(
						IF
						(
							kswert.fk_id_kswertvorlage IS NULL,
							(
								(
									r1.rechnungsbetrag
									-
									IFNULL(
									(
										SELECT
											SUM(rechnungzahlung_1.skonto)
										FROM
											rechnungzahlung AS rechnungzahlung_1
										WHERE
											rechnungzahlung_1.fk_id_rechnung = r1.id
									) ,0)
								)
								/
								100
								*
								kswert.prozent
							),
							(
								kswertvorlage.wert
								/
								(
									SELECT
										SUM(kswertvorlage_1.wert)
									FROM
										kswertvorlage AS kswertvorlage_1
									WHERE
										kswertvorlage_1.fk_id_ks = kswertvorlage.fk_id_ks
								)
								*
								(
									r1.rechnungsbetrag
									-
									(
										IFNULL(
											(
												SELECT
													SUM(rechnungzahlung_1.skonto)
												FROM
													rechnungzahlung AS rechnungzahlung_1
												WHERE
													rechnungzahlung_1.fk_id_rechnung = r1.id
											),
											0
										)
									)
								)
								*
								kswert.prozent
								/
								100
							)
						)
					) AS VerteilterBetrag
				FROM
					(rechnung AS r1 RIGHT JOIN kswert ON kswert.fk_id_rechnung = r1.id)
						LEFT JOIN kswertvorlage ON kswert.fk_id_kswertvorlage = kswertvorlage.id				
				WHERE
					r1.fk_id_og = id_og AND
					r1.rechnungsdatum BETWEEN startdate AND enddate  AND
					r1.fk_id_kostengruppe = id_kostengruppe AND
					kswert.fk_id_wohneinheit = id_wohneinheit
				GROUP BY
					r1.fk_id_kostengruppe
					,kswert.fk_id_wohneinheit
			),
			0
		)
	);
END$$

DELIMITER ;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;