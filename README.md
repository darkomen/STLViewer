# STLViewer

**Un catálogo visual de diseños para impresión 3D, desarrollado como aplicación nativa para macOS.**

STLViewer permite explorar los proyectos de una biblioteca organizada con **STL Manager**, consultar su documentación, localizar archivos y abrir modelos en **OrcaSlicer** sin salir del catálogo. La aplicación está escrita en **Swift y SwiftUI** y utiliza las convenciones de carpetas y metadatos compartidas con STL Manager.

> **Versión congelada: v0.3.8 (17 de octubre de 2026).** Esta versión corresponde al estado validado funcionalmente en el Mac de desarrollo. Es un proyecto en evolución, no una distribución comercial ni una versión final del visor 3D.

## Funciones principales

### Catálogo visual

- Visualización de proyectos en **tarjetas** o en **lista**.
- Búsqueda por nombres y categorías, con filtros desde la barra lateral.
- Miniaturas persistentes: utiliza la portada guardada, fotografías del proyecto, vistas previas incorporadas en archivos 3MF o vistas generadas desde STL compatibles, según disponibilidad.
- Portada personalizada desde la ficha de un proyecto, escogiendo una imagen existente o importando otra nueva.
- Reconocimiento de **colecciones protegidas** configuradas por STL Manager.

### Ficha de proyecto e inspector

- En el modo **Tarjetas**, se abre la ficha individual en una ventana flotante.
- En el modo **Lista**, un **inspector lateral** permite cambiar de proyecto sin abrir y cerrar ventanas; se puede ampliar a la ficha completa.
- Lectura de `README.md` con formato Markdown habitual y posibilidad de editarlo en proyectos gestionados.
- Edición de nombre de carpeta, categorías, URL de origen y portada, donde los permisos lo permiten.

### Explorador de archivos y OrcaSlicer

- Árbol de carpetas desplegable, similar a la vista de lista de Finder.
- Acceso a los archivos y carpetas reales del proyecto sin reorganizarlos.
- Apertura rápida de modelos compatibles en **OrcaSlicer** desde la ficha o desde el **menú contextual del catálogo**.
- Si un proyecto contiene varios modelos, ofrece un submenú o un selector con búsqueda y **selección múltiple**, en función del número de archivos.
- Acceso directo para mostrar la carpeta del proyecto en **Finder**.

### Añadir archivos a proyectos existentes

- Importación de varios archivos de una sola vez desde la ficha.
- Copia de los archivos a su ubicación correspondiente (`models/`, `sources/`, `images/` u `others/`), conservando los originales.
- Comprobación de duplicados y verificación mediante **SHA-256**.
- Actualización del inventario `.stlmanager.json` y de la sección **Archivos** del `README.md`.
- Confirmación visual con resumen de los archivos incorporados.

### Ajustes de biblioteca

- Visualización de la ruta de biblioteca y recuentos de proyectos/colecciones.
- Acciones **Mostrar en Finder**, **Cambiar biblioteca** y **Olvidar biblioteca** (esta última con confirmación).
- Acceso persistente mediante los permisos y mecanismos de selección de carpetas de macOS.

## Organización esperada de la biblioteca

STLViewer está diseñado para trabajar sobre una biblioteca previamente organizada con STL Manager. Un ejemplo de proyecto gestionado:

```text
Diseños/
├── .stlmanager/
│   └── library.json                 # Reglas de colecciones y carpetas
├── MiProyecto/
│   ├── models/                      # STL, 3MF, STEP, OBJ, etc.
│   ├── sources/                     # Archivos editables y fuentes CAD
│   ├── images/
│   │   └── stlviewer-preview.png    # Portada del proyecto, si existe
│   ├── others/                      # Archivos adicionales, cuando procede
│   ├── README.md
│   └── .stlmanager.json             # Metadatos e inventario
└── OtraColeccionProtegida/           # Se trata como solo lectura
```

`others/` y algunas otras carpetas pueden no existir en todos los proyectos. La configuración de protección de `library.json` tiene prioridad: **STLViewer no debe escribir dentro de colecciones declaradas de solo lectura**.

## Requisitos y compilación

- Un **Mac con una versión de macOS compatible con el target configurado en Xcode**.
- **Xcode** y el proyecto de STLViewer, compilado con Swift/SwiftUI.
- Dependencia Swift Package Manager: [ZIPFoundation](https://github.com/weichsel/ZIPFoundation), usada para leer las previsualizaciones incrustadas en archivos 3MF.
- **OrcaSlicer** instalado si se desea utilizar la opción de enviar modelos al laminador.
- Para disfrutar de todas las funciones de catalogación, una biblioteca de **STL Manager** con los metadatos esperados.

### Puesta en marcha

1. Abre el proyecto de STLViewer en Xcode.
2. Comprueba que **ZIPFoundation** está añadido al target de la aplicación.
3. En **Signing & Capabilities → App Sandbox**, utiliza permisos de **lectura y escritura para carpetas elegidas por el usuario** cuando vayas a editar proyectos gestionados.
4. Selecciona el target de STLViewer y compila (`⌘B`); ejecuta (`⌘R`).
5. Al abrir STLViewer, selecciona la raíz de tu biblioteca de diseños y concede acceso.
6. En **Ajustes de STLViewer** puedes consultar o cambiar después la ubicación de esa biblioteca.

> **Importante:** los permisos de edición solo deben utilizarse sobre proyectos gestionados. Haz una copia de seguridad antes de probar funciones que renombren carpetas o modifiquen metadatos y README.

## Cómo utilizarlo

| Necesitas… | Haz esto |
| --- | --- |
| Encontrar un diseño | Usa la búsqueda o el filtro de categorías |
| Explorar fotografías y portadas | Cambia a **Tarjetas** |
| Revisar muchos proyectos rápidamente | Cambia a **Lista** y utiliza el inspector |
| Abrir un modelo en OrcaSlicer | Haz clic derecho sobre el proyecto y selecciona el archivo |
| Consultar modelos y subcarpetas | Entra en **Archivos** y despliega el árbol |
| Añadir un STL nuevo | **Archivos → Añadir archivos…** |
| Cambiar la imagen del catálogo | Ficha → **Configuración → Portada** |
| Editar documentación | Ficha → **README → Editar** |
| Cambiar la biblioteca | **Ajustes de STLViewer** |

## Seguridad y conservación de archivos

- La aplicación distingue entre **proyectos gestionados** y **colecciones protegidas**.
- Las miniaturas automáticas y los cambios de portada no modifican la geometría STL/3MF de origen.
- Al incorporar archivos, se copian al proyecto; no se mueven los originales.
- El inventario y el README se actualizan para los nuevos archivos, respetando la documentación existente.
- Se recomienda mantener una copia de seguridad de la biblioteca, especialmente antes de operaciones de renombrado o importación masiva.

## Limitaciones conocidas

- No todos los STL o 3MF pueden generar una miniatura automática; algunos proyectos necesitan **portada manual**.
- La visualización de Markdown cubre el formato habitual, pero **no implementa por completo GitHub Flavored Markdown** (por ejemplo, algunas tablas o elementos complejos).
- La ficha actual no incorpora aún un **visor 3D interactivo completo** con giro y zoom del modelo.
- Los formatos CAD como STEP no cuentan con renderizado nativo completo dentro del catálogo.
- La exploración profunda e indexación individual de colecciones protegidas muy grandes queda pendiente de una etapa posterior.

## Versionado

La versión de referencia congelada es **v0.3.8**, con el icono naranja del Benchy y la lupa. Los detalles de evolución se encuentran en [CHANGELOG.md](CHANGELOG.md), y el resumen de este hito en [RELEASE_NOTES_v0.3.8.md](RELEASE_NOTES_v0.3.8.md).

## Relación con STL Manager

Ambas aplicaciones comparten la estructura de biblioteca, pero tienen objetivos diferentes:

- **STL Manager:** detectar, importar, normalizar y organizar archivos de diseño.
- **STLViewer:** consultar, buscar, documentar, gestionar y enviar archivos de esa biblioteca al laminador.

El código de STLViewer es un proyecto independiente. No incorpora ni redistribuye los modelos 3D que puedas guardar en tu biblioteca.

## Estado del proyecto

Proyecto personal en desarrollo. Esta versión se conserva como **punto estable de referencia** antes de seguir con nuevas funcionalidades.
