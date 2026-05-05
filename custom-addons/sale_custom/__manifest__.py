# -*- coding: utf-8 -*-
{
    'name': 'sale_custom',
    'version': '19.0.1.0.0',
    'summary': 'Short description',
    'category': 'Uncategorized',
    'author': '',
    'license': 'LGPL-3',
    'depends': ['base'],
    'data': [
        # Load order matters: security first, then data, then views
        'security/ir.model.access.csv',
        # 'data/config_data.xml',
        'views/sale_custom_views.xml',
        'views/menu.xml',
    ],
    'demo': [
        # 'demo/demo_data.xml',
    ],
    'assets': {
        'web.assets_backend': [
            'sale_custom/static/src/components/**/*.xml',
            'sale_custom/static/src/components/**/*.js',
            'sale_custom/static/src/stores/**/*.js',
        ],
    },
    'installable': True,
    'auto_install': False,
    'application': False,
}

