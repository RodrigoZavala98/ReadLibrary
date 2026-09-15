# Lector — traspaso de contexto

Estado a **14 de septiembre de 2026**, commit «EPUB: analizador propio,
renderizador de XHTML y lector generalizado».
Repositorio: <https://github.com/RodrigoZavala98/ReadLibrary> (**público**).

Aplicación Android de lectura de libros, escrita en Flutter, **completamente
local**: sin cuentas, sin servidor y sin enviar nada a ningún sitio.

La propuesta original está en `lector de libros.txt` y el mockup en
`Component 1.svg` (2571×1282, seis pantallas). Ambos siguen siendo útiles como
referencia visual, pero **varias de sus decisiones se revisaron** — ver
«Decisiones cerradas».

---

## 1. Entorno

### Lo que hay instalado (equipo corporativo Windows, sin admin)

| Componente | Ruta |
|---|---|
| Flutter 3.47.4 / Dart 3.13.3 | `C:\Users\uif37020\dev\flutter` |
| JDK 17.0.20 (Temurin) | `C:\Users\uif37020\dev\jdk-17.0.20.1+1` |
| Android SDK (plataforma 36, build-tools 36.1.0) | `C:\Users\uif37020\dev\android-sdk` |
| Proyecto | `D:\Projects\lector\app` |

`JAVA_HOME`, `ANDROID_HOME` y `ANDROID_SDK_ROOT` están definidas a nivel de
usuario. El Java 8 del sistema se dejó intacto en el `PATH` a propósito, para no
romper aplicaciones corporativas que dependan de él.

### No se puede compilar el APK en este equipo

El proxy de la empresa intercepta TLS y sustituye los certificados. Java tiene su
propio almacén de confianza, separado del de Windows, y no conoce la CA
corporativa. Gradle falla con `PKIX path building failed`.

**No intentes arreglarlo tocando certificados** — se descartó expresamente para
no chocar con las políticas del dominio.

Lo que **sí** funciona en local:

```bash
export PATH="/c/Users/uif37020/dev/flutter/bin:$PATH"
export JAVA_HOME="/c/Users/uif37020/dev/jdk-17.0.20.1+1"
cd D:/Projects/lector/app
flutter analyze
flutter test
```

El APK lo produce **GitHub Actions** (`.github/workflows/build-apk.yml`): analiza,
pasa la suite dos veces (UTC y UTC+14) y compila. El artefacto es
`lector-debug-apk`, se descarga desde la pestaña Actions y se instala
directamente — va en modo depuración porque un *release* sin firmar no se puede
instalar en un teléfono.

**El `push` lo tiene que hacer el usuario**: no hay gestor de credenciales
configurado y la autenticación de GitHub abre navegador.

---

## 2. Arquitectura

```
app/lib/
├── main.dart              arranque; construye AppServices y monta la app
├── app_services.dart      inyección de dependencias + AppScope (InheritedWidget)
├── domain/                Dart puro: modelos y reglas. Sin dependencias de UI
├── formats/               un lector por formato de fichero
├── data/                  persistencia en JSON
├── core/theme/            paletas y tipografía
├── shell/                 armazón de navegación
└── ui/                    pantallas
```

La regla que sostiene todo: **`domain/` no sabe nada de Flutter ni de cómo se
guardan las cosas**. Por eso está tan bien cubierto por pruebas — se ejecuta sin
dispositivo, que en este equipo es la única forma de verificar nada.

### Las tres piezas que conviene entender antes de tocar nada

**`domain/book_locator.dart` — la posición de lectura.**
No es un número de página, y esa es la decisión más importante del proyecto. En
un EPUB el texto se re-maqueta: subir el tamaño de letra cambia la numeración y
el lector pierde su sitio. Cada formato guarda su propio localizador
(`PageLocator` para PDF y CBZ, `CharLocator` para TXT, `EpubLocator` para EPUB) y
el porcentaje de avance va **aparte**, solo para pintar barras. Un localizador
que no corresponde al formato se descarta al leerlo.

**`domain/book_source.dart` — la interfaz común de lectura.**
`BookSource` se especializa en `FixedLayoutSource` (páginas inmutables: PDF, CBZ)
y `ReflowableSource` (texto que se re-maqueta: TXT, EPUB, FB2). Añadir un formato
no debería obligar a tocar ni una línea de interfaz de usuario. Ciclo de vida
siempre `open()` → uso → `dispose()`.

**`data/library_repository.dart` — el acceso a la biblioteca.**
Es una interfaz a propósito. Detrás hay un índice JSON que se reescribe entero en
cada guardado, con escritura atómica en tres pasos (temporal → respaldo → nuevo)
para que un corte a mitad no deje la biblioteca truncada.

---

## 3. Qué funciona hoy

- **Importar** un fichero: se copia al almacenamiento privado, se detecta el
  formato, se rechaza con explicación lo que aún no se soporta, y se evita
  duplicar por huella de contenido.
- **Mi Biblioteca**: lista con progreso, estado vacío, botón de alta.
- **Leer un TXT**: detección de codificación, troceado, superficie de papel,
  controles ocultos hasta tocar el centro, navegación por partes.
- **Leer un EPUB**: analizador propio en Dart puro (ZIP, OPF, índice por NCX o
  por `nav`), renderizador de XHTML con la tipografía del lector, imágenes de
  los capítulos, y los EPUB con DRM rechazados con una explicación.
- **La posición sobrevive** a cerrar la aplicación, y retomar un libro te deja
  dentro del fragmento donde estabas.
- **Mi Refugio**: saludo personalizado, anillo de racha, aviso cuando está en
  riesgo, tarjeta de continuar leyendo.
- **Mi Viaje**: calendario del mes con la intensidad de cada día, navegable
  hacia atrás hasta la primera lectura; métricas del mes, resumen de todo el
  historial y trece insignias con su progreso.
- **Perfil local**: nombre opcional y meta diaria, detrás del avatar.
- **Registro de lectura**: cronómetro que cuenta tiempo delante del libro, no
  tiempo con el libro abierto.

**309 pruebas**, análisis estático limpio. Todo verificado en dispositivo real
salvo EPUB, pendiente del próximo APK.

---

## 4. Qué falta, en el orden que recomiendo

### 4.1 Mis Notas

`domain/highlight.dart` tiene el modelo. Falta **todo** lo demás: capturar la
selección de texto en el lector, persistir, y la pantalla de la sección.

### 4.2 PDF y CBZ

- **PDF → `pdfrx` 2.6.1** (MIT, 449k descargas, mantenido). **No uses
  `syncfusion_flutter_pdfviewer`**: es comercial, y su licencia gratuita tiene
  topes de facturación y de número de desarrolladores que una empresa como esta
  casi seguro no cumple.
- **CBZ → `archive`**, que ya es dependencia directa desde EPUB. Ojo: hasta
  ahora este documento decía que venía como dependencia transitiva, y era
  falso; no estaba en `pubspec.lock`.

### 4.3 Lo pequeño que falta

- Portadas reales (hoy hay una tarjeta con la inicial) → `palette_generator` para
  el color dominante.
- Ajustes de lectura: `ReadingStyle` existe con tamaño, interlineado, serifa y
  superficie (papel / sepia / noche), pero está fijado al valor por defecto y no
  hay interfaz para cambiarlo.
- Notificaciones: `ReaderProfile.reminder` existe pero nada lo programa.
  `flutter_local_notifications` 22.3.1. **Usa programación inexacta** para no
  pedir `SCHEDULE_EXACT_ALARM`, que Google Play audita; un aviso de lectura no
  necesita precisión al minuto. Harán falta `POST_NOTIFICATIONS` (permiso en
  runtime desde Android 13) y `RECEIVE_BOOT_COMPLETED`.
- Borrar un libro de la biblioteca.
- Las insignias no guardan **cuándo** se consiguieron: se sabe que están, no el
  día. Deducir la fecha exigiría recorrer el historial criterio a criterio.
- Colecciones: el campo `collection` existe en el modelo, sin interfaz.
- Del EPUB quedan fuera, a sabiendas: el **CSS** del libro (manda la tipografía
  del lector, que es la decisión de fondo), las **tablas** —se aplanan a una
  línea por fila— y los **enlaces internos**, que se pintan pero no navegan.
- Los **`<title>` de los documentos** no se leen para titular capítulos sin
  índice: obligaría a descomprimir el libro entero al abrirlo. Se numeran.

---

## 5. Formatos descartados, y por qué

Están declarados en `BookFormat` con `isSupported: false`, para que la biblioteca
pueda mostrarlos en gris y **explicar** en vez de fallar.

- **CBR** — es un contenedor RAR. No existe descompresor en Dart puro y la
  licencia de `unrar` prohíbe expresamente reimplementar el algoritmo. Solo sería
  viable con bindings nativos vía FFI, lo que en entorno corporativo exige
  revisión legal. El importador sugiere convertir a CBZ.
- **FB2** — técnicamente viable (es XML), pero `fb2_parse` lleva cinco años sin
  mantenerse y usa APIs de WebView ya eliminadas. Habría que escribir el
  analizador a mano.
- **RTF** — no hay ningún analizador mantenido en el ecosistema Dart.

---

## 6. Decisiones cerradas (no conviene reabrirlas sin motivo)

1. **Sin backend.** Se eliminó el «estás en el top 5 % de lectores» del mockup
   porque exigía cuentas, servidor y RGPD. Decisión explícita del usuario.
2. **Cuatro secciones**: Mi Refugio, Mi Biblioteca, Mis Notas, Mi Viaje. Los
   ajustes **no** son un destino de navegación: viven detrás del avatar. Se
   descartó «Explorar» (exigía catálogo en línea) y «Perfil» como pestaña.
3. **Dos mundos visuales.** Alrededor de la lectura, índigo nocturno con
   tipografía sans. Dentro del libro, papel cálido con serifa y sin cromo. Se
   descartaron glassmorphism y neumorfismo: caros de renderizar y desfasados.
4. **Nada de `BackdropFilter` animado a pantalla completa** — es de lo más caro
   que hay en Flutter y se nota en gama media. Para el fondo dinámico, degradado
   **precalculado** desde el color de la portada.
5. **El día de lectura empieza a las 4:00**, no a medianoche. Quien cierra el
   libro a la 1:30 del martes está terminando su lunes.
6. **Intensidad del calendario medida contra la meta**, no contra el máximo
   histórico como hace GitHub. Con el criterio relativo, un día de maratón deja
   el resto del año en gris y los meses dejan de ser comparables.
7. **Semana empezando en lunes.**
8. **Los subrayados guardan el texto literal**, no solo la posición. Es duplicar
   datos a propósito: si se reemplaza el fichero por otra edición, la cita
   sobrevive.
9. **Los libros se copian** al almacenamiento privado. Desde Android 11 el
   permiso del selector es temporal; una ruta externa deja de abrirse al día
   siguiente. `MANAGE_EXTERNAL_STORAGE` es motivo de rechazo en Play.
10. **JSON en lugar de Isar**, detrás de una interfaz. Isar exige generación de
    código y binarios nativos, imposibles de verificar en este equipo. Para
    cientos de libros el JSON sobra. Si algún día hace falta: `isar_community`
    3.3.2 (el `isar` original lleva tres años sin versión estable).
11. **EPUB con analizador propio**, no con `flutter_epub_viewer`. El mockup ya
    pedía control visual, pero el argumento que cerró la decisión es otro: en
    este equipo no se puede compilar un APK, así que las pruebas son la única
    verificación posible antes de subir, y de un lector sobre WebView no se
    puede probar ni una línea. De paso, el `<script>` de un EPUB descargado de
    cualquier sitio no se ejecuta nunca, porque no hay motor que lo ejecute.
    Se descartó también `epub_pro`: pide `xml ^6.5.0` contra el 7.0.1 que ya
    arrastra el proyecto y lleva más de un año sin publicarse.
12. **La posición en un EPUB es documento del lomo + milésimas**, no un CFI. Un
    CFI se genera contra el DOM de Epub.js; sin ese motor no lo sabría
    interpretar nadie.
13. **`applicationId` = `com.readlibrary.lector`.** Era `com.uif37020.lector` —
    el número de empleado — y es **permanente** una vez publicas en Play. No lo
    cambies otra vez.

---

## 7. Trampas del entorno de pruebas

Esto es lo que más tiempo ha costado en todo el proyecto. Léelo **antes** de
escribir una prueba de widget.

**`pumpAndSettle` nunca termina si hay un `CircularProgressIndicator`.** Anima sin
parar, así que «asentar» no ocurre jamás y la prueba se cuelga hasta agotar su
plazo interno de diez minutos. Usa el helper `asentar()` que hay en los tests.

**`testWidgets` corre con reloj simulado.** Las operaciones reales de disco se
resuelven en el bucle de eventos de verdad, así que un `await repository.save()`
sin envolver en `tester.runAsync` **no vuelve nunca**.

**El orden importa.** Hay que pintar un fotograma *después* del toque para que la
pantalla se construya y arranque su carga, y *solo entonces* ceder tiempo real.
Al revés, la carga empieza cuando ya no queda tiempo.

**Cada operación de disco necesita su propia ventana de tiempo real.** Una cadena
de varias escrituras disparada desde la zona simulada se queda a medias. Si el
test dispara una acción que encadena guardados, lanza el toque **dentro** de
`runAsync`.

**`pump()` sin duración no avanza el reloj simulado**, así que las animaciones de
transición entre rutas no llegan a terminar.

**Nunca acoples una prueba al reloj de la máquina.** CI corre en UTC y el equipo
de desarrollo en UTC−6: una prueba que dependa de la hora pasa en un sitio y
falla en el otro. Ya ocurrió dos veces. El workflow ahora repite la suite bajo
UTC+14 para delatarlo.

### Y dos trampas del propio Flutter

**No llames a `AppScope.of(context)` desde `dispose()`.** Por debajo usa
`dependOnInheritedWidgetOfExactType`, prohibido sobre un widget desactivado.
Lanza «Looking up a deactivated widget's ancestor is unsafe» justo en el momento
de guardar, y de forma **invisible**: la app no se cierra, simplemente no pasa
nada. Captura los servicios en `didChangeDependencies`.

**No interrogues a un `ScrollController` desde `dispose()`.** Flutter desmonta
los hijos antes que los padres: para entonces el `ListView` ya no existe y la
posición está desacoplada. Anota el avance mientras el widget vive.

---

## 8. Limitaciones conocidas

- **La posición de lectura es una estimación.** Se reparte el desplazamiento de
  forma lineal sobre el rango de caracteres del fragmento. Te devuelve a la misma
  pantalla, no al carácter exacto. Hacerlo exacto exigiría medir cada línea tras
  maquetarla.
- **El historial de sesiones crece sin límite**, porque la racha más larga
  necesita todo el pasado. Unas 7.000 entradas en cinco años de lectura intensa,
  algo más de medio megabyte que se carga entero al arrancar. El techo está
  lejos, pero existe; la salida sería guardar totales por día.
- **El APK de depuración pesa 74 MB.** Un *release* firmado bajaría a 15–20 MB, y
  dividiendo por arquitectura a menos de 10.
- **No se extraen portadas** de los ficheros todavía.
- **Dentro de un capítulo de EPUB la posición es una fracción**, no un punto del
  texto: devuelve a la misma pantalla, no a la misma palabra. El tramo sobre el
  que aproxima es un capítulo, del mismo orden que el fragmento sobre el que ya
  aproxima el lector de TXT.
- **El progreso de un EPUB se reparte por el peso en bytes** de cada documento
  del lomo, no por su número de palabras. Un capítulo con mucho marcado o muchas
  imágenes pesa más de lo que se tarda en leerlo.
- **Las insignias se derivan del historial**, no se guardan al desbloquearse.
  A cambio de no tener un fichero más que pueda desincronizarse, borrar de la
  biblioteca un libro terminado puede volver a bloquear una insignia, y cambiar
  un criterio reescribe el pasado.

---

## 9. Costumbres del proyecto

- Todo el código y los comentarios en **español**.
- Los comentarios explican **por qué**, no qué. Si una decisión tiene una
  alternativa evidente que se descartó, el comentario dice por qué.
- **Cada corrección lleva su prueba de regresión, y la prueba se valida
  reintroduciendo el fallo.** Una prueba que nunca has visto fallar no demuestra
  nada. Esta costumbre cazó un falso positivo —un test que fallaba por un motivo
  distinto del que creía comprobar— y, en Mi Viaje, una prueba que seguía
  pasando con el fallo dentro: comprobaba que cambiar de mes borraba el día
  seleccionado, pero eso no se podía ver desde fuera porque la selección lleva
  mes y año. Se borró el código muerto y la prueba pasó a comprobar lo que de
  verdad importa, que la lectura de un mes no se atribuya a otro.
- Ante un fallo que no se entiende a la primera: **instrumenta con trazas** en
  lugar de encadenar hipótesis. En el último fallo se descartaron tres teorías
  equivocadas antes de hacerlo, y la instrumentación lo resolvió en un intento.
