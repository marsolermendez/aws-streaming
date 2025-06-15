# app.py

import json
# ¡Importamos render_template!
from flask import Flask, jsonify, render_template
from flask_cors import CORS

def cargar_productos_desde_json():
    try:
        with open('productos.json', 'r') as json_file:
            productos_cargados = json.load(json_file)
            print(f"-> {len(productos_cargados)} productos cargados correctamente desde productos.json")
            return productos_cargados
    except FileNotFoundError:
        print("!!! ERROR: No se encontró el archivo 'productos.json'.")
        return []
    except Exception as e:
        print(f"!!! ERROR al cargar productos desde JSON: {e}")
        return []

app = Flask(__name__)
CORS(app)

productos = cargar_productos_desde_json()

def guardar_productos_en_json():
    global productos
    try:
        with open('productos.json', 'w') as json_file:
            json.dump(productos, json_file, indent=4)
        print(f"-> Stock actualizado y guardado en productos.json")
    except Exception as e:
        print(f"!!! ERROR al guardar productos en JSON: {e}")

# --- NUEVA RUTA PARA SERVIR EL FRONTEND ---
@app.route('/')
def index():
    """
    Esta función sirve el archivo index.html como la página principal.
    Flask automáticamente busca el archivo en la carpeta 'templates'.
    """
    return render_template('index.html')

# --- RUTAS DE LA API (sin cambios) ---
@app.route('/api/productos', methods=['GET'])
def get_productos():
    return jsonify(productos)

@app.route('/api/comprar/<int:producto_id>', methods=['POST'])
def comprar_producto(producto_id):
    global productos
    producto_encontrado = None
    for p in productos:
        if p['id'] == producto_id:
            producto_encontrado = p
            break

    if producto_encontrado is None:
        return jsonify({"error": "Producto no encontrado"}), 404

    if producto_encontrado['stock'] > 0:
        producto_encontrado['stock'] -= 1
        guardar_productos_en_json()
        return jsonify({
            "mensaje": "Compra realizada con éxito",
            "producto": producto_encontrado
        }), 200
    else:
        return jsonify({
            "error": "No hay stock disponible para este producto",
            "producto": producto_encontrado
        }), 400

if __name__ == '__main__':
    app.run(debug=True, port=5001)

