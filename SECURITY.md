# Política de seguridad

Astral mantiene un proceso privado para recibir, evaluar y corregir reportes de
seguridad sobre contratos, scripts y configuración operativa incluidos en este
repositorio.

## Versiones mantenidas

| Versión | Estado |
| --- | --- |
| Rama `main` | Mantenida |
| Última etiqueta publicada | Mantenida |
| Versiones anteriores | Solo si se indica expresamente |

Los despliegues pueden usar parámetros distintos. Incluye siempre red,
dirección, bloque y configuración relevante al comunicar un comportamiento
observado sobre una instancia concreta.

## Alcance

Se consideran dentro del alcance:

- contratos en `src/`;
- vaults de colateral y tokens de recibo;
- contabilidad de deuda, suministro, índices y reservas;
- validaciones de borrow, withdraw y liquidación;
- oráculos y adaptadores de precio;
- modelos de tipos;
- configuración de roles, pausas y parámetros;
- scripts mantenidos en este repositorio;
- vistas cuando influyen en decisiones operativas.

Normalmente quedan fuera:

- credenciales comprometidas fuera del repositorio;
- interfaces no mantenidas aquí;
- despliegues de terceros modificados;
- indisponibilidad de proveedores externos sin impacto contractual;
- parámetros de mercado no recomendados por operadores del protocolo.

## Comunicación privada

Usa el canal privado de avisos de seguridad del repositorio o el contacto
indicado por los mantenedores. No publiques detalles técnicos en issues, foros,
redes sociales o canales comunitarios antes de completar la coordinación.

Incluye, si es posible:

- componente afectado;
- commit, versión o dirección desplegada;
- red y bloque de referencia;
- condiciones previas;
- comportamiento esperado y observado;
- impacto técnico y económico;
- secuencia mínima de verificación;
- trazas, pruebas o transacciones relevantes;
- medidas temporales que puedan reducir riesgo.

No adjuntes claves privadas, frases semilla, credenciales ni datos personales.
Si el material requiere cifrado, solicita primero un canal adecuado.

## Respuesta

El equipo intentará seguir estos plazos:

1. acuse de recibo en dos días laborables;
2. evaluación inicial en cinco días laborables;
3. actualización semanal mientras continúe el análisis;
4. coordinación de corrección, despliegue y comunicación según el alcance
   confirmado.

La prioridad se determina por fondos en riesgo, reproducibilidad, permisos
necesarios, alcance entre mercados y disponibilidad de mitigaciones.

## Investigación responsable

Para proteger usuarios y redes:

- trabaja en una red local o fork controlado siempre que sea posible;
- no accedas a cuentas de terceros;
- no degradas servicios;
- no retengas fondos que no te pertenezcan;
- limita transacciones públicas al mínimo necesario;
- conserva evidencias suficientes para una verificación segura;
- coordina la publicación con los mantenedores.

Esta política no autoriza actividad contra sistemas de terceros ni sustituye
asesoramiento jurídico.

## Dependencias

Los comportamientos de riesgo en dependencias deben comunicarse también a sus
mantenedores cuando corresponda. Si una dependencia afecta a contratos
desplegados, permite preparar medidas operativas antes de divulgar detalles.

## Divulgación coordinada

La fecha y el contenido de cualquier publicación se acordarán después de
disponer de una corrección o de medidas razonables para proteger usuarios. El
reconocimiento se realizará cuando la persona informante lo solicite y sea
apropiado.
