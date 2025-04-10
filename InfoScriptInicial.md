# JoseManuel

Creación y automatización del script de conectividad de maquina X a la maquina server

Establecer las variables

El Script actualiza el repositorio mediante el comando update/upgrade

Instala el paquete sshpass para poder realizar conexión de manera directa sin necesidad de escribir la fingerprint.

Conexión sshpass al usuario del servidor abriendo un EOF, un bloque de comandos que han de ejecutarse dentro de esta conexión. Dicho bloque contiene:

Cambiar/establecer la contraseña del usuario root para usar el ansible a posteriori.

Le damos nombre a la maquina server.

Cambiamos los parametros del archivo sshd_config para permitir la conexion ssh del root.

Creación de copia de seguridad en caso de que no exista del antiguo Netplan por posibles fallos.

Modifcación del archivo netplan para realizar establecerle una ip fija de la cual conectarnos posteriormente desde ansible.

Aplicación de los cambios del netplan. y fin del EOF

Comprobación de la conectividad entre las dos maquinas mediante PING

Conexión sshpass al usuario root.
