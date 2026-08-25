# RTorrentRemote

App nativa de macOS (SwiftUI) para controlar una instancia remota de **rTorrent** por XML-RPC sobre HTTP.

## Requisito en el servidor

rTorrent no habla HTTP de forma nativa: expone su RPC por un socket **SCGI**. Para que esta app
pueda conectarse necesitas un proxy delante de ese socket que traduzca HTTP ⇄ SCGI. Dos opciones típicas:

### Opción A: nginx + `scgi_pass` (recomendada, permite HTTPS y auth básica)

En `rtorrent.rc`:
```
network.scgi.open_local = /home/USER/.rtorrent.sock
```
o, si prefieres TCP interno:
```
network.scgi.open_port = 127.0.0.1:5000
```

En nginx:
```nginx
server {
    listen 443 ssl;
    server_name torrent.tu-dominio.com;

    ssl_certificate     /ruta/fullchain.pem;
    ssl_certificate_key /ruta/privkey.pem;

    location /RPC2 {
        # Autenticación básica opcional pero muy recomendable
        auth_basic "rTorrent";
        auth_basic_user_file /etc/nginx/.htpasswd;

        include scgi_params;
        scgi_pass unix:/home/USER/.rtorrent.sock;
        # o: scgi_pass 127.0.0.1:5000;
    }
}
```

En la app, configura en Ajustes:
- Host: `torrent.tu-dominio.com`
- Puerto: `443`, HTTPS activado
- Ruta: `/RPC2`
- Usuario/contraseña: los del `.htpasswd`

### Opción B: `socat` (rápida para pruebas, sin HTTPS/auth)

```bash
socat TCP-LISTEN:5001,reuseaddr,fork UNIX-CONNECT:/home/USER/.rtorrent.sock
```
Esto no habla HTTP realmente, así que en producción usa la opción A. Para pruebas locales por
túnel SSH puedes hacer `ssh -L 5001:localhost:5001 usuario@servidor` y apuntar la app a
`http://localhost:5001/` con HTTPS desactivado (nginx sigue siendo necesario si quieres XML-RPC
sobre HTTP real; socat solo por sí solo no traduce SCGI a HTTP).

## Abrir el proyecto

1. Copia esta carpeta (`RTorrentRemote`) a
   `/Users/miguel/Documents/XCode/Utilidades_MacOS/RTorrentRemote`.
2. Abre `RTorrentRemote.xcodeproj` con Xcode 16 (o el que tengas instalado; el proyecto usa
   `objectVersion = 56`, compatible con Xcode 15/16).
3. Selecciona tu equipo de firma en el target `RTorrentRemote` → *Signing & Capabilities*
   (con "Automatically manage signing" basta para ejecutar en local).
4. Ejecuta con ⌘R. Al primer arranque se abre el panel de Ajustes para configurar el servidor.

## Funcionalidades incluidas

- Lista de torrents con progreso, velocidades, ratio, estado, filtros y búsqueda.
- Acciones: iniciar / detener / pausar / reanudar / eliminar / verificar hash.
- Añadir torrents por magnet/URL o subiendo un `.torrent` desde el Mac.
- Etiquetas (usa `d.custom1`, el mismo campo que usa ruTorrent para "label"). Al añadir un
  torrent con etiqueta, la app calcula el info-hash real (desde el magnet o parseando el
  bencode del `.torrent`) para etiquetar exactamente el torrent correcto, sin adivinar.
- Detalle por torrent con lista de archivos y prioridad de descarga por archivo.
- Límites globales de velocidad de subida/bajada.
- RSS: pantalla funcional, pero solo operativa si tu build de rTorrent expone los métodos
  `rss.*` (no viene activado en todas las distribuciones/paquetes). Si no está disponible, la
  app te lo indica en pantalla en lugar de fallar en silencio.
- Contraseña guardada en el Keychain de macOS; el resto de la configuración en `UserDefaults`.

## Notas técnicas

- El cliente XML-RPC (`Networking/XMLRPCClient.swift` + `XMLRPCParser.swift`) está escrito con
  `Foundation` puro (URLSession + XMLParser), sin dependencias externas.
- La app usa App Sandbox con `network.client` y `files.user-selected.read-only` únicamente.
- Si tu proxy usa un certificado autofirmado, activa "Aceptar certificados no verificados" en
  Ajustes: la app confiará en cualquier certificado servido por ese host (uso pensado para
  servidores domésticos propios, no para redes no confiables).
