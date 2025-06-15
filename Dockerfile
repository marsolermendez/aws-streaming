# Paso 1: Usar una imagen oficial de Python como base
FROM python:3.9-slim

# Paso 2: Establecer el directorio de trabajo dentro del contenedor
WORKDIR /app

# --- CAMBIOS IMPORTANTES ---

# Paso 3: Copiar el archivo de requisitos PRIMERO
# Esto permite a Docker cachear la capa de dependencias.
COPY requirements.txt .

# Paso 4: Instalar las dependencias
# Esta capa solo se reconstruirá si requirements.txt cambia.
RUN pip install --no-cache-dir -r requirements.txt

# Paso 5: Copiar el RESTO de los archivos de la aplicación
# Esto incluye app.py y, crucialmente, productos.json.
COPY . .

# --- FIN DE LOS CAMBIOS ---

# Paso 6: Exponer el puerto en el que correrá la aplicación
EXPOSE 8080

# Paso 7: El comando para ejecutar la aplicación usando Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
