# app.py

import os
from flask import Flask, jsonify, render_template
from flask_cors import CORS
from sqlalchemy import create_engine, Column, Integer, String, Float
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base

# --- 1. Configuración de la Conexión a la Base de Datos ---
# Leemos las credenciales de las variables de entorno que nos pasará App Runner.
db_user = os.environ.get('RDS_USER')
db_pass = os.environ.get('RDS_PASS')
db_host = os.environ.get('RDS_HOST')
db_name = os.environ.get('RDS_DB')

# Creamos la URL de conexión para SQLAlchemy.
DATABASE_URL = f"postgresql+psycopg2://{db_user}:{db_pass}@{db_host}/{db_name}"

# Creamos el "motor" de la base de datos, que gestiona las conexiones.
engine = create_engine(DATABASE_URL)
# Creamos una "fábrica" de sesiones para interactuar con la BBDD.
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
# Base para nuestros modelos de datos (ORM).
Base = declarative_base()


# --- 2. Definición del Modelo de la Tabla 'Product' ---
# Esto define la estructura de nuestra tabla 'products' en la base de datos.
class Product(Base):
    __tablename__ = "products"
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String, index=True)
    descripcion = Column(String)
    precio = Column(Float)
    stock = Column(Integer)
    imagen = Column(String)


# --- 3. Función para Inicializar la Base de Datos ---
def init_db():
    # Crea la tabla 'products' en la BBDD si no existe.
    Base.metadata.create_all(bind=engine)
    
    # Abrimos una sesión para verificar y rellenar los datos.
    db = SessionLocal()
    # Si la tabla está vacía, la rellenamos con los productos iniciales.
    if db.query(Product).count() == 0:
        print("-> La tabla 'products' está vacía. Insertando datos iniciales...")
        initial_products = [
            {'id': 1, 'nombre': 'Laptop Pro X', 'descripcion': 'Potente laptop para profesionales y creativos.', 'precio': 1200.00, 'stock': 15, 'imagen': 'https://placehold.co/600x400/2d3748/ffffff?text=Laptop+Pro+X'},
            {'id': 2, 'nombre': 'Mouse Inalámbrico Ergo', 'descripcion': 'Diseño ergonómico para máxima comodidad.', 'precio': 45.50, 'stock': 30, 'imagen': 'https://placehold.co/600x400/4a5568/ffffff?text=Mouse+Ergo'},
            {'id': 3, 'nombre': 'Teclado Mecánico RGB', 'descripcion': 'Retroiluminación RGB y switches de alta precisión.', 'precio': 89.99, 'stock': 8, 'imagen': 'https://placehold.co/600x400/718096/ffffff?text=Teclado+RGB'},
            {'id': 4, 'nombre': 'Monitor UltraWide 34\"', 'descripcion': 'Monitor curvo para una experiencia inmersiva.', 'precio': 450.00, 'stock': 12, 'imagen': 'https://placehold.co/600x400/a0aec0/ffffff?text=Monitor+34'}
        ]
        for p_data in initial_products:
            db.add(Product(**p_data))
        db.commit()
        print("-> Datos iniciales insertados.")
    else:
        print("-> La tabla 'products' ya contiene datos.")
    db.close()


# --- 4. Aplicación Flask ---
app = Flask(__name__)
CORS(app)

# Al arrancar, nos aseguramos de que la BBDD está lista.
init_db()


# --- 5. Endpoints de la API (leyendo desde RDS) ---
@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/productos', methods=['GET'])
def get_productos():
    db = SessionLocal()
    products_from_db = db.query(Product).all()
    db.close()
    
    products_dict = [
        {"id": p.id, "nombre": p.nombre, "descripcion": p.descripcion, "precio": p.precio, "stock": p.stock, "imagen": p.imagen} 
        for p in products_from_db
    ]
    return jsonify(products_dict)

@app.route('/api/comprar/<int:producto_id>', methods=['POST'])
def comprar_producto(producto_id):
    db = SessionLocal()
    product_to_buy = db.query(Product).filter(Product.id == producto_id).first()

    if not product_to_buy:
        db.close()
        return jsonify({"error": "Producto no encontrado"}), 404

    if product_to_buy.stock > 0:
        product_to_buy.stock -= 1
        db.commit()
        product_info = {"id": product_to_buy.id, "nombre": product_to_buy.nombre, "stock": product_to_buy.stock}
        db.close()
        return jsonify({"mensaje": "Compra realizada con éxito", "producto": product_info})
    else:
        db.close()
        return jsonify({"error": "No hay stock disponible para este producto"}), 400


if __name__ == '__main__':
    # Este bloque solo se usa para pruebas locales.
    app.run(debug=True, port=5001)
