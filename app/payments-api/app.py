from flask import Flask, jsonify

app = Flask(__name__)


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/payments/<payment_id>")
def get_payment(payment_id):
    return jsonify(id=payment_id, status="approved", amount=130000, currency="COP")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
