python3 << EOF
import re
import vim
import os
class VerilogParse:
    def __init__(self):
        self.buffer = vim.current.buffer
        # self.buffer = open('location_module.v', 'r', encoding='utf-8').readlines()
        # self.buffer = open('pos_fifo.v', 'r', encoding='utf-8').readlines()

        self.dict = {}

        self.content = self.delete_all_comment()
        self.port = self.paser_port(self.content)
        self.module_name = self.parse_module_name(self.content)
        self.module_para = self.parse_module_para()

    def parse_module_name(self, content):
        """
        找到文件的模块名称
        :param content:
        :return:
        """
        for line in content:
            if line.find('module') != -1:
                module_name = line.split(' ')[1]
                break

        return module_name

    def parse_module_para(self):
        """
        找到文件的模块参数，存放到列表
        :return:
        """
        module_para = []
        para_dict = {}
        for line in self.content:
            if line.find('input') != -1 or line.find('output') != -1 or line.find('inout') != -1 :
                break
            elif line.find('parameter') == 0:
                line = line.replace('parameter', '').strip()
                para_dict['para_name'] = line[:line.find('=')].strip()
                para_dict['para_value'] = line[line.find('=')+1:].replace(',', '').strip().rstrip()

                dict = para_dict.copy()
                module_para.append(dict)

        return module_para

    def delete_all_comment(self):
        """
        删除文件里的所有注释代码
        """
        content = []
        comment_flag = 0
        for line in self.buffer:
            line = line.strip()

            if line.find('/*') == 0 and line.find('*/') > 2:
                 continue
            elif line.find('/*') == 0:
                comment_flag = 1
                continue
            elif line.find('*/') != -1:
                comment_flag = 0
                continue

            if comment_flag == 0:
                if line.find('//') != -1:
                    line = line[:line.find('//')]
                    line = line.rstrip()
                if line:
                    content.append(line)
        return content

    def paser_port(self, content):
        def parse_expression(expression, params):
            """
            解析表达式并计算其值。支持参数替换和基本的数学运算。
            :param expression: 字符串表达式，如 'IRC_RII_UW-1'
            :param params: 参数字典，如 {'IRC_RII_UW': 18}
            :return: 计算后的整数值
            """
            # 用参数值替换表达式中的参数名
            for param in params:
                expression = expression.replace(param, str(params[param]))

            try:
                # 计算表达式值
                return eval(expression)
            except Exception as e:
                print(f"Error evaluating expression: {expression}, Error: {e}")
                return None

        """
        找到Verilog里的所有端口, 并解析端口位宽及参数
        :param content: 包含Verilog代码的字符串列表
        :return: 端口信息列表
        """
        port = []
        params = {}

        for i in content:
            line = i.strip()

            # 提取parameter定义
            if line.startswith('parameter'):
                # 匹配parameter定义，例如 parameter IRC_RII_UW = 18;
                pattern = r'\s*parameter\s+(\w+)\s*=\s*(.*?)(?:,\s*|\s*$)'
                # pattern = r'\s*parameter\s+(\w+)\s*=\s*(.*?)(?:,|\s*\))'
                match = re.match(pattern, line)
                if match:
                    param_name = match.group(1)
                    param_value = match.group(2)
                    params[param_name] = int(eval(param_value))

            # 去掉 '=' 后面所有字符
            if '=' in line:
                line = line.split('=')[0].strip()

            # 去掉 ',' 后面所有字符
            if ',' in line:
                line = line.split(',')[0].strip()

            # 去掉 ';' 后面所有字符
            if ';' in line:
                line = line.split(';')[0].strip()

            # 去掉注释
            if '//' in line:
                line = line.split('//')[0].strip()

            # 默认always语句后不会再有端口声明
            if 'always' in line:
                break
            else:
                if line.startswith('input') or line.startswith('output') or line.startswith('inout'):
                    if line.startswith('input'):
                        self.dict['port_type'] = 'input'
                        line = line[len('input'):].strip()
                    elif line.startswith('output'):
                        self.dict['port_type'] = 'output'
                        line = line[len('output'):].strip()
                    elif line.startswith('inout'):
                        self.dict['port_type'] = 'inout'
                        line = line[len('inout'):].strip()

                    if line.startswith('reg'):
                        self.dict['vari_type'] = 'reg'
                        line = line[len('reg'):].strip()
                    else:
                        self.dict['vari_type'] = 'wire'
                        line = line.replace('wire', '').strip()

                    if '[' in line:
                        # 提取位宽表达式
                        width_expr = line[line.find('[') + 1:line.find(']')]
                        start, end = map(str.strip, width_expr.split(':'))

                        # 解析表达式并计算位宽
                        start_val = parse_expression(start, params)
                        end_val = parse_expression(end, params)
                        if start_val is not None and end_val is not None:
                            width_int = abs(start_val - end_val) + 1
                            self.dict['width'] = str(width_int)
                        else:
                            self.dict['width'] = 'unknown'

                        # 提取端口名称
                        line = line[line.find(']') + 1:].strip()
                        self.dict['name'] = line
                    else:
                        self.dict['width'] = '1'
                        self.dict['name'] = line

                    dict_copy = self.dict.copy()
                    port.append(dict_copy)

        return port

    def find_sub_module(self):
        pass

    def creat_instance_snippet(self):
        """
        生成模块的例化代码片段
        :return:
        """
        module_name = self.parse_module_name(self.content)
        port = self.port
        module_para = self.module_para

        max_length = 0
        for p in port:
            if max_length < len(p['name']):
                max_length = len(p['name'])
        for p in module_para:
            if max_length < len(p['para_name']):
                max_length = len(p['para_name'])
        max_length = (max_length//4+1)*4  # tab 可以对齐

        if module_para:
            cnt = 0
            instance_snippet = module_name + ' #\n(\n'
            for ele in module_para:
                if cnt + 1 == len(module_para):  # 最后一个参数
                    instance_snippet += '    .' + ele['para_name'] + (max_length - len(ele['para_name'])) * ' ' + '(' + '  ' + \
                                 ele['para_value'] + (max_length - len(ele['para_value'])) * ' ' + ')'
                    instance_snippet += '\n)\n' + module_name + 'Ex01\n(\n'
                else:
                    instance_snippet += '    .' + ele['para_name'] + (max_length - len(ele['para_name']))*' ' + '(' + '  ' + ele['para_value'] +  (max_length-len(ele['para_value']))*' ' + '),\n'
                    cnt += 1
        else:
            instance_snippet = module_name + ' ' + module_name + 'Ex01' + '\n(\n'

        direction_map = {
            'input': 'i',
            'output': 'o',
            'inout': 'io'
        }

        cnt = 0

        for ele in port:
            # 获取端口的方向和位宽
            direction = ele.get('port_type', '')
            width = ele.get('width', '')

            # 将方向转换为缩略词
            direction_abbr = direction_map.get(direction, direction)

            # 构建注释字符串
            comment = f" //{direction_abbr}_{width}bit"

            if cnt+1 == len(port):
                instance_snippet += '    .' + ele['name'] + (max_length-len(ele['name']))*' ' + '(' + '  ' + ele['name'] + (max_length-len(ele['name'])+4)*' ' + ')' + comment
                instance_snippet += '\n);'
            else:
                instance_snippet += '    .' + ele['name'] + (max_length-len(ele['name']))*' ' + '(' + '  ' + ele['name'] +  (max_length-len(ele['name'])+4)*' ' + '),' + comment + '\n'
            cnt += 1

        vim.command('let @+= "%s"' % instance_snippet)
        return instance_snippet

    def create_interface_file(self):
        """
        在当前文件目录下，生成基于当前文件的 interface 文件
        :return:
        """
        module_name = self.parse_module_name(self.content)
        port = self.port
        file_name = module_name + '_bfm.svh'
        interface_content = 'interface ' + module_name + '_bfm;\n'
        for p in port:
            interface_content += '    '
            interface_content += 'logic '

            if p['width'] != '1':
                interface_content += '[' + p['width'] + '-1 : 0' + ']    ' + p['name'] + ';\n'
            else:
                interface_content += p['name'] + ';\n'
        interface_content += '\nendinterface\n'

        vim.command('let @+= "%s"' % interface_content)
        vim.command('echo @+')

        #if os.path.exists(file_name) == False:
        #    f = open(file_name, 'w')
        #    f.write(interface_content)
        #    f.close()

    def create_class_file(self):
        """
        在当前文件目录下，生成基于当前文件的 class 文件
        :return:
        """
        module_name = self.parse_module_name(self.content)
        file_name = module_name + '_drive.svh'
        class_content = '`ifndef ' + module_name.upper() + '_SVH\n'
        class_content += '`define ' + module_name.upper() + '_SVH\n\n'
        class_content += 'class ' + module_name + '_drive;\n'
        class_content += '    virtual ' + module_name + '_bfm bfm;\n\n'
        class_content += '    function new(virtual ' + module_name + '_bfm b, string name);\n'
        class_content += '        bfm = b;\n'
        class_content += '    endfunction\n\n'

        class_content += 'extern virtual task execute ();\n\n'
        class_content += 'endclass\n\n'
        class_content += 'task ' + module_name + '_drive::execute ();\n\n'
        class_content += 'endtask\n\n'
        class_content += 'endclass\n'

        vim.command('let @+= "%s"' % class_content)
        vim.command('echo @+')
        #if os.path.exists(file_name) == False:
        #    f = open(file_name, 'w')
        #    f.write(class_content)
        #    f.close()

    def create_testbench_file(self):
        module_name = self.parse_module_name(self.content)
        port_list = self.port
        file_name = module_name + '_tb.sv'
        tb_content = '`timescale 1ns / 1ps\n\n'
        tb_content += 'module ' + module_name + '_tb();\n\n'
        for line in port_list:
            if line['port_type'] == 'input':
                if  line['width'] == '1':
                    tb_content += 'logic ' + line['name'] + ' = 0;\n'
                else:
                    tb_content += 'logic [' + line['width'] + '] ' + line['name'] + ' = 0;\n'
            else:
                if  line['width'] == '1':
                    tb_content += 'logic ' + line['name'] + ';\n'
                else:
                    tb_content += 'logic [' + line['width'] + '] ' + line['name'] + ';\n'
        tb_content += '\n'
        tb_content += self.creat_instance_snippet();
        tb_content += '\n\nendmodule\n'

        vim.command('let @+= "%s"' % tb_content)
        vim.command('echo @+')

        #if os.path.exists(file_name) == False:
        #    vim.command('let @+= "%s"' % tb_content)
        #    f = open(file_name, 'w')
        #    f.write(tb_content)
        #    f.close()
EOF

let s:com = "py3"
function! instance#generate()
    if &filetype == 'verilog'
        exec s:com 'VerilogParse().creat_instance_snippet()'
        echo @+
    else
        echomsg "Only support verilog file"
    end
endfunction

function! instance#interface()
    if &filetype == 'verilog'
        exec s:com 'VerilogParse().create_interface_file()'
    else
        echomsg "Only support verilog file"
    end
endfunction

function! instance#class()
    if &filetype == 'verilog'
        exec s:com 'VerilogParse().create_class_file()'
    else
        echomsg "Only support verilog file"
    end
endfunction

function! instance#testbench()
    if &filetype == 'verilog'
        exec s:com 'VerilogParse().create_testbench_file()'
    else
        echomsg "Only support verilog file"
    end
endfunction
