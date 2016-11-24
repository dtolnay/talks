""" 
A style for Pygments
""" 
from setuptools import setup 

setup( 
    name         = 'dtolnay', 
    version      = '1.0', 
    description  = __doc__, 
    author       = "David Tolnay", 
    install_requires = ['pygments'],
    packages     = ['dtolnay'], 
    entry_points = '''
    [pygments.styles]
    dtolnay = dtolnay:DTStyle
    [pygments.lexers]
    rusty = dtolnay:Rusty
    '''
) 
