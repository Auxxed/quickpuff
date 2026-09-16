"""QuickPuff — Peak Pro companion for Linux."""

from .ble import LoraxError, PuffcoBLE

__version__ = "0.5.1"
__all__ = ["LoraxError", "PuffcoBLE", "__version__"]
