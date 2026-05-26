from fastapi import APIRouter
import numpy as np

router = APIRouter()

@router.get('')
def hello_world() -> dict:
    return {'msg': 'Hello, World!'}

@router.get("/matrix")
def matrix_multiply():
    a = np.random.rand(10, 10) #kitty
    b = np.random.rand(10, 10) #puppie
    product = np.matmul(a, b)
    return {
            "matrix_a": a.tolist(),
            "matrix_b": b.tolist(),
            "product": product.tolist(),
    }
