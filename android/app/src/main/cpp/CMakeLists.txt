# SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
# SPDX-License-Identifier: GPL-3.0-or-later

cmake_minimum_required(VERSION 3.22.1)
project(saber_memlock)

add_library(saber_memlock SHARED saber_memlock.cpp)
find_library(log-lib log)
target_link_libraries(saber_memlock ${log-lib})
