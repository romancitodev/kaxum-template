BEGIN;

-- Infraestructura
INSERT INTO recinto (id_recinto, nombre, tipo, capacidad) VALUES
  (1, 'Sabana norte',         'terrestre', 10),
  (2, 'Selva del jaguar',     'terrestre',  4),
  (3, 'Aviario',              'terrestre', 30),
  (4, 'Tanque de tiburones',  'acuático',   6),
  (5, 'Laguna de pingüinos',  'acuático',  12);

-- 1:1 con recinto (solo los acuáticos)
INSERT INTO tanque (id_recinto, volumen_litros, temp_objetivo) VALUES
  (4, 500000, 24.0),
  (5, 150000, 12.0);

-- Animales
INSERT INTO especie (id_especie, nombre_comun, estado_conservacion) VALUES
  (1, 'León',                   'Vulnerable'),
  (2, 'Jaguar',                 'Casi amenazado'),
  (3, 'Pingüino de Magallanes', 'Casi amenazado'),
  (4, 'Tiburón toro',           'Vulnerable'),
  (5, 'Guacamayo rojo',         'Preocupación menor'),
  (6, 'Jirafa',                 'Vulnerable');

INSERT INTO animal (id_animal, nombre, fecha_nacimiento, id_especie, id_recinto) VALUES
  (1,  'Nala',     '2014-05-10', 1, 1),
  (2,  'Mufasa',   '2013-08-22', 1, 1),
  (3,  'Kiara',    '2021-03-15', 1, 1),
  (4,  'Tupá',     '2018-11-02', 2, 2),
  (5,  'Aurora',   '2019-06-30', 2, 2),
  (6,  'Pipo',     '2022-10-05', 3, 5),
  (7,  'Coco',     '2022-11-12', 3, 5),
  (8,  'Colmillo', '2017-01-01', 4, 4),
  (9,  'Rubí',     '2019-04-20', 5, 3),
  (10, 'Gala',     '2017-09-09', 6, 1);

-- Personal
INSERT INTO empleado (id_empleado, nombre, cargo) VALUES
  (1, 'Marta Ibarra',    'director'),
  (2, 'Diego Salas',     'veterinario'),
  (3, 'Lucía Ferreyra',  'veterinario'),
  (4, 'Tomás Aguirre',   'cuidador'),
  (5, 'Camila Ríos',     'cuidador'),
  (6, 'Nicolás Paz',     'biólogo marino'),
  (7, 'Sofía Lamas',     'guía'),
  (8, 'Bruno Vega',      'guía');

-- N:M empleado - recinto (Camila cubre tres recintos; el recinto 1 tiene dos personas)
INSERT INTO asignacion (id_empleado, id_recinto, turno) VALUES
  (4, 1, 'mañana'),
  (5, 1, 'tarde'),
  (5, 2, 'tarde'),
  (5, 3, 'mañana'),
  (6, 4, 'mañana'),
  (6, 5, 'tarde');

-- Consultas (las atienden los veterinarios: empleados 2 y 3)
INSERT INTO consulta (id_consulta, id_animal, id_empleado, fecha, diagnostico) VALUES
  (1,  1, 2, '2024-03-12', 'Control anual sin hallazgos'),
  (2,  8, 3, '2024-05-20', 'Infección cutánea leve'),
  (3,  6, 3, '2024-07-02', 'Parásitos intestinales'),
  (4, 10, 2, '2025-01-15', 'Desgaste de pezuña'),
  (5,  4, 2, '2025-06-10', 'Control posvacunación'),
  (6,  2, 2, '2026-08-10', 'Cojera leve en pata trasera');

-- Visitantes, entradas y actividades
INSERT INTO visitante (id_visitante, nombre, email) VALUES
  (1, 'Valentina Gómez', 'valentina.gomez@example.com'),
  (2, 'Martín Suárez',   'martin.suarez@example.com'),
  (3, 'Julieta Romero',  'julieta.romero@example.com'),
  (4, 'Raúl Benítez',    'raul.benitez@example.com');

INSERT INTO entrada (id_entrada, id_visitante, fecha_visita, precio) VALUES
  (1, 1, '2026-09-19',  8000.00),
  (2, 1, '2026-09-19',  4000.00),
  (3, 2, '2026-09-19', 11000.00),
  (4, 3, '2026-09-20',  7200.00),
  (5, 4, '2026-09-20',  5000.00);

INSERT INTO actividad (id_actividad, nombre, horario, cupo, id_recinto) VALUES
  (1, 'Alimentación de leones',          '11:00', 15, 1),
  (2, 'Show de pingüinos',               '15:00', 30, 5),
  (3, 'Recorrido nocturno por la selva', '20:00', 12, 2),
  (4, 'Encuentro con guacamayos',        '12:30', 10, 3);

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

-- Resincronizar las secuencias IDENTITY, así los próximos INSERT sin id
-- no chocan con los del seed.
DO $$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      ('recinto', 'id_recinto'), ('especie', 'id_especie'),
      ('animal', 'id_animal'), ('empleado', 'id_empleado'),
      ('consulta', 'id_consulta'), ('visitante', 'id_visitante'),
      ('entrada', 'id_entrada'), ('actividad', 'id_actividad')
    ) AS x(tabla, col)
  LOOP
    EXECUTE format(
      'SELECT setval(pg_get_serial_sequence(%L, %L), COALESCE(MAX(%I), 1)) FROM %I',
      t.tabla, t.col, t.col, t.tabla);
  END LOOP;
END $$;

COMMIT;
