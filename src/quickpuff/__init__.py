"""QuickPuff — Peak Pro companion for Linux."""

from .ble import LoraxError, PuffcoBLE

__version__ = "0.6.0"
__all__ = ["LoraxError", "PuffcoBLE", "__version__"]
