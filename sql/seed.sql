-- =====================================================================
-- seed.sql - Zoológico + Acuario (datos de prueba, todo ficticio)
-- Motor: PostgreSQL. Asume que las tablas ya existen (nombres y
-- columnas según el DER).
-- Si tus PK son GENERATED ALWAYS AS IDENTITY, agregá
-- OVERRIDING SYSTEM VALUE a cada INSERT.
-- =====================================================================

-- Para recargar desde cero, descomentá esto antes de correr el seed:
-- TRUNCATE zona, recinto, tanque, medicion_agua, familia, especie,
--   habitat, especie_habitat, animal, chip, movimiento_animal,
--   alimento, dieta, proveedor, suministro, cargo, empleado,
--   veterinario, asignacion_recinto, consulta, medicamento,
--   consulta_medicamento, visitante, tipo_entrada, entrada,
--   actividad, reserva
--   RESTART IDENTITY CASCADE;

BEGIN;

-- ---------------------------------------------------------------------
-- Infraestructura
-- ---------------------------------------------------------------------
INSERT INTO zona (id_zona, nombre, tipo, superficie_m2) VALUES
  (1, 'Sabana africana',   'terrestre', 12000),
  (2, 'Selva tropical',    'terrestre',  8000),
  (3, 'Acuario',           'acuática',   5000),
  (4, 'Área veterinaria',  'terrestre',  1500);

INSERT INTO recinto (id_recinto, nombre, capacidad_max, id_zona) VALUES
  (1, 'Sabana norte',         10, 1),
  (2, 'Selva del jaguar',      4, 2),
  (3, 'Aviario',              30, 2),
  (4, 'Tanque de tiburones',   6, 3),
  (5, 'Laguna de pingüinos',  12, 3),
  (6, 'Cuarentena',            4, 4);

-- 1:1 con recinto: solo los recintos acuáticos
INSERT INTO tanque (id_recinto, volumen_litros, tipo_agua, temp_objetivo) VALUES
  (4, 500000, 'salada', 24.0),
  (5, 150000, 'salada', 12.0);

-- La medición 4 está fuera de rango a propósito (para probar alertas)
INSERT INTO medicion_agua (id_medicion, id_tanque, fecha_hora, temperatura, ph, salinidad) VALUES
  (1, 4, '2026-09-18 06:00', 24.1, 8.10, 35.0),
  (2, 4, '2026-09-18 07:00', 24.0, 8.09, 35.1),
  (3, 4, '2026-09-18 08:00', 24.3, 8.11, 34.9),
  (4, 4, '2026-09-18 09:00', 27.8, 7.40, 35.0),
  (5, 5, '2026-09-18 06:00', 12.2, 8.05, 33.0),
  (6, 5, '2026-09-18 07:00', 12.4, 8.04, 33.1),
  (7, 5, '2026-09-18 08:00', 12.1, 8.06, 33.0);

-- ---------------------------------------------------------------------
-- Taxonomía y hábitats
-- ---------------------------------------------------------------------
INSERT INTO familia (id_familia, nombre, clase) VALUES
  (1, 'Felidae',        'Mammalia'),
  (2, 'Spheniscidae',   'Aves'),
  (3, 'Carcharhinidae', 'Chondrichthyes'),
  (4, 'Psittacidae',    'Aves'),
  (5, 'Giraffidae',     'Mammalia');

INSERT INTO especie (id_especie, nombre_comun, nombre_cientifico, estado_conservacion, id_familia) VALUES
  (1, 'León',                   'Panthera leo',            'Vulnerable',         1),
  (2, 'Jaguar',                 'Panthera onca',           'Casi amenazado',     1),
  (3, 'Pingüino de Magallanes', 'Spheniscus magellanicus', 'Casi amenazado',     2),
  (4, 'Tiburón toro',           'Carcharhinus leucas',     'Vulnerable',         3),
  (5, 'Guacamayo rojo',         'Ara macao',               'Preocupación menor', 4),
  (6, 'Jirafa',                 'Giraffa camelopardalis',  'Vulnerable',         5);

INSERT INTO habitat (id_habitat, nombre, bioma) VALUES
  (1, 'Sabana',         'pastizal'),
  (2, 'Selva tropical', 'bosque húmedo'),
  (3, 'Costa marina',   'marino'),
  (4, 'Río y estuario', 'agua dulce y salobre');

-- N:M especie - hábitat
INSERT INTO especie_habitat (id_especie, id_habitat) VALUES
  (1, 1),
  (2, 2),
  (3, 3),
  (4, 3),
  (4, 4),
  (5, 2),
  (6, 1);

-- ---------------------------------------------------------------------
-- Personal (el supervisor se inserta antes que sus dependientes)
-- ---------------------------------------------------------------------
INSERT INTO cargo (id_cargo, nombre) VALUES
  (1, 'Director'),
  (2, 'Veterinario'),
  (3, 'Cuidador'),
  (4, 'Guía'),
  (5, 'Biólogo marino');

INSERT INTO empleado (id_empleado, dni, nombre, apellido, fecha_ingreso, id_cargo, id_supervisor) VALUES
  (1, '20111222', 'Marta',   'Ibarra',   '2012-03-01', 1, NULL),
  (2, '27333444', 'Diego',   'Salas',    '2015-06-15', 2, 1),
  (3, '30555666', 'Lucía',   'Ferreyra', '2018-02-01', 2, 1),
  (4, '28777888', 'Tomás',   'Aguirre',  '2016-09-12', 3, 1),
  (5, '33999000', 'Camila',  'Ríos',     '2019-04-01', 3, 4),
  (6, '31222333', 'Nicolás', 'Paz',      '2017-11-20', 5, 1),
  (7, '35444555', 'Sofía',   'Lamas',    '2021-01-10', 4, 1),
  (8, '36666777', 'Bruno',   'Vega',     '2022-07-05', 4, 7);

-- 1:1 con empleado (especialización)
INSERT INTO veterinario (id_empleado, matricula, especialidad) VALUES
  (2, 'MP-4521', 'Fauna silvestre'),
  (3, 'MP-5033', 'Animales acuáticos');

-- N:M empleado - recinto, con historial (fecha_hasta NULL = vigente)
INSERT INTO asignacion_recinto (id_empleado, id_recinto, fecha_desde, fecha_hasta, turno) VALUES
  (4, 1, '2020-01-01', NULL,         'mañana'),
  (5, 1, '2019-04-01', '2021-12-31', 'tarde'),
  (5, 2, '2022-01-01', NULL,         'tarde'),
  (5, 3, '2022-01-01', NULL,         'mañana'),
  (6, 4, '2018-01-01', NULL,         'mañana'),
  (6, 5, '2023-01-15', NULL,         'tarde');

-- ---------------------------------------------------------------------
-- Animales (los padres se insertan antes que las crías)
-- Kiara (3) es hija de Nala (1) y Mufasa (2)
-- ---------------------------------------------------------------------
INSERT INTO animal (id_animal, nombre, sexo, fecha_nacimiento, fecha_ingreso, id_especie, id_recinto, id_madre, id_padre) VALUES
  (1,  'Nala',     'F', '2014-05-10', '2016-02-01', 1, 1, NULL, NULL),
  (2,  'Mufasa',   'M', '2013-08-22', '2016-02-01', 1, 1, NULL, NULL),
  (3,  'Kiara',    'F', '2021-03-15', '2021-03-15', 1, 1, 1,    2),
  (4,  'Tupá',     'M', '2018-11-02', '2019-04-10', 2, 2, NULL, NULL),
  (5,  'Aurora',   'F', '2019-06-30', '2020-01-20', 2, 2, NULL, NULL),
  (6,  'Pipo',     'M', '2022-10-05', '2023-01-15', 3, 5, NULL, NULL),
  (7,  'Coco',     'F', '2022-11-12', '2023-01-15', 3, 5, NULL, NULL),
  (8,  'Colmillo', 'M', '2017-01-01', '2018-06-01', 4, 4, NULL, NULL),
  (9,  'Rubí',     'F', '2019-04-20', '2020-05-05', 5, 3, NULL, NULL),
  (10, 'Gala',     'F', '2017-09-09', '2018-03-03', 6, 1, NULL, NULL);

-- 1:1 con animal (no todos tienen chip)
INSERT INTO chip (id_animal, codigo, fecha_colocacion) VALUES
  (1,  'CHIP-0001', '2016-02-05'),
  (2,  'CHIP-0002', '2016-02-05'),
  (4,  'CHIP-0004', '2019-04-15'),
  (5,  'CHIP-0005', '2020-01-25'),
  (8,  'CHIP-0008', '2018-06-10'),
  (10, 'CHIP-0010', '2018-03-10');

-- N:M animal - recinto (historial de traslados)
-- Casi todos entran por Cuarentena (6). Mufasa (2) tiene ida y vuelta.
INSERT INTO movimiento_animal (id_movimiento, id_animal, id_origen, id_destino, fecha, motivo) VALUES
  (1, 10, 6, 1, '2018-03-20', 'Fin de cuarentena'),
  (2,  4, 6, 2, '2019-05-10', 'Fin de cuarentena'),
  (3,  9, 6, 3, '2020-05-20', 'Fin de cuarentena'),
  (4,  6, 6, 5, '2023-01-25', 'Fin de cuarentena'),
  (5,  7, 6, 5, '2023-01-25', 'Fin de cuarentena'),
  (6,  2, 1, 6, '2026-08-10', 'Tratamiento veterinario'),
  (7,  2, 6, 1, '2026-08-14', 'Alta veterinaria');

-- ---------------------------------------------------------------------
-- Alimentación
-- ---------------------------------------------------------------------
INSERT INTO alimento (id_alimento, nombre, unidad, stock) VALUES
  (1, 'Carne vacuna',      'kg', 120),
  (2, 'Pescado',           'kg',  80),
  (3, 'Frutas y semillas', 'kg',  40),
  (4, 'Heno',              'kg', 300);

-- N:M especie - alimento
INSERT INTO dieta (id_especie, id_alimento, cantidad_diaria, frecuencia) VALUES
  (1, 1,  6.0, '1 vez por día'),
  (2, 1,  4.5, '1 vez por día'),
  (2, 2,  0.5, '3 veces por semana'),
  (3, 2,  1.2, '2 veces por día'),
  (4, 2,  8.0, '1 vez por día'),
  (5, 3,  0.4, '2 veces por día'),
  (6, 4, 15.0, '2 veces por día'),
  (6, 3,  1.0, '1 vez por día');

INSERT INTO proveedor (id_proveedor, razon_social, cuit) VALUES
  (1, 'Frigorífico Del Sur S.A.',  '30-71234567-8'),
  (2, 'Pesquera Atlántico S.R.L.', '30-70987654-3'),
  (3, 'Granja Verde S.A.',         '30-68123456-1');

-- N:M proveedor - alimento (el pescado lo venden dos proveedores)
INSERT INTO suministro (id_proveedor, id_alimento, precio_unitario) VALUES
  (1, 1, 7200.00),
  (1, 2, 5900.00),
  (2, 2, 5400.00),
  (3, 3, 3100.00),
  (3, 4,  900.00);

-- ---------------------------------------------------------------------
-- Salud (dosis ilustrativas, no clínicas)
-- ---------------------------------------------------------------------
INSERT INTO consulta (id_consulta, id_animal, id_veterinario, fecha, diagnostico) VALUES
  (1,  1, 2, '2024-03-12', 'Control anual sin hallazgos'),
  (2,  8, 3, '2024-05-20', 'Infección cutánea leve'),
  (3,  6, 3, '2024-07-02', 'Parásitos intestinales'),
  (4, 10, 2, '2025-01-15', 'Desgaste de pezuña'),
  (5,  4, 2, '2025-06-10', 'Control posvacunación'),
  (6,  2, 2, '2026-08-10', 'Cojera leve en pata trasera');

INSERT INTO medicamento (id_medicamento, nombre, principio_activo) VALUES
  (1, 'Ivermectina', 'ivermectina'),
  (2, 'Amoxicilina', 'amoxicilina'),
  (3, 'Meloxicam',   'meloxicam');

-- N:M consulta - medicamento (la consulta 2 tiene dos medicamentos)
INSERT INTO consulta_medicamento (id_consulta, id_medicamento, dosis, dias_tratamiento) VALUES
  (2, 2, '20 mg/kg cada 24 h',   10),
  (2, 3, '0,1 mg/kg cada 24 h',   3),
  (3, 1, '0,2 mg/kg dosis única', 1),
  (4, 3, '0,1 mg/kg cada 24 h',   5),
  (6, 3, '0,1 mg/kg cada 24 h',   4);

-- ---------------------------------------------------------------------
-- Visitantes y actividades
-- ---------------------------------------------------------------------
INSERT INTO visitante (id_visitante, dni, nombre, email) VALUES
  (1, '40111222', 'Valentina Gómez', 'valentina.gomez@example.com'),
  (2, '38222333', 'Martín Suárez',   'martin.suarez@example.com'),
  (3, '42333444', 'Julieta Romero',  'julieta.romero@example.com'),
  (4, '29444555', 'Raúl Benítez',    'raul.benitez@example.com');

INSERT INTO tipo_entrada (id_tipo, nombre, precio_base) VALUES
  (1, 'General',       8000.00),
  (2, 'Niño',          4000.00),
  (3, 'Jubilado',      5000.00),
  (4, 'Combo acuario', 11000.00);

-- La entrada 4 pagó menos que el precio base (descuento)
INSERT INTO entrada (id_entrada, id_visitante, id_tipo, fecha_visita, precio_pagado) VALUES
  (1, 1, 1, '2026-09-19',  8000.00),
  (2, 1, 2, '2026-09-19',  4000.00),
  (3, 2, 4, '2026-09-19', 11000.00),
  (4, 3, 1, '2026-09-20',  7200.00),
  (5, 4, 3, '2026-09-20',  5000.00);

INSERT INTO actividad (id_actividad, nombre, horario, cupo, id_recinto, id_guia) VALUES
  (1, 'Alimentación de leones',        '11:00', 15, 1, 7),
  (2, 'Show de pingüinos',             '15:00', 30, 5, 8),
  (3, 'Recorrido nocturno por la selva', '20:00', 12, 2, 7),
  (4, 'Encuentro con guacamayos',      '12:30', 10, 3, 8);

-- N:M entrada - actividad
INSERT INTO reserva (id_entrada, id_actividad, cantidad_personas) VALUES
  (1, 1, 1),
  (2, 1, 1),
  (1, 2, 1),
  (2, 2, 1),
  (3, 2, 1),
  (3, 4, 1),
  (4, 3, 1),
  (5, 4, 1),
  (5, 2, 1);

-- ---------------------------------------------------------------------
-- Resincronizar secuencias (si las PK son SERIAL/IDENTITY), así los
-- próximos INSERT sin id no chocan con los del seed. Si la columna no
-- tiene secuencia, no hace nada.
-- ---------------------------------------------------------------------
DO $$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      ('zona', 'id_zona'), ('recinto', 'id_recinto'),
      ('medicion_agua', 'id_medicion'), ('familia', 'id_familia'),
      ('especie', 'id_especie'), ('habitat', 'id_habitat'),
      ('animal', 'id_animal'), ('movimiento_animal', 'id_movimiento'),
      ('alimento', 'id_alimento'), ('proveedor', 'id_proveedor'),
      ('cargo', 'id_cargo'), ('empleado', 'id_empleado'),
      ('consulta', 'id_consulta'), ('medicamento', 'id_medicamento'),
      ('visitante', 'id_visitante'), ('tipo_entrada', 'id_tipo'),
      ('entrada', 'id_entrada'), ('actividad', 'id_actividad')
    ) AS x(tabla, col)
  LOOP
    EXECUTE format(
      'SELECT setval(pg_get_serial_sequence(%L, %L), COALESCE(MAX(%I), 1)) FROM %I',
      t.tabla, t.col, t.col, t.tabla);
  END LOOP;
END $$;

COMMIT;
