[![build status](https://secure.travis-ci.org/selead/amz.png)](http://travis-ci.org/selead/amz)
# amz - консоль управления виртуальными машинами amazon ec2

## Установка

        $ npm install amz -g

   После установки необходимо задать параметры по умолчанию:

        $ amz config set --awsAccessKey=ACCESS_KEY --awsSecretKey=XXXXX --awsKeypairName=default --awsImageId=ami-XXXXXXXX

## Запуск из командной строки
   
   Основные команды:

        $ amz start [options]
        $ amz stop  [options]
        $ amz log
        $ amz history
        $ amz add-script
        $ amz list-scripts
        $ amz dump-script
        $ amz list-ip
        $ amz bind-ip options

### Скрипты запуска
    
    При старте виртуальной машины можно выполнять пользовательские скрипты. Для хранения таких скриптов amz использует репозиторий.

### Добавление скрипта в репозиторий

    $ amz add-script --script script-name --path path/to/script

    Скрипт добавляется или заменяет уже существующий с тем же именем.

### Список скриптов

    $ amz list-scripts

    Показать список скриптов

### Выгрузить скрипт в рабочий каталог (для правки)

    $ amz dump-script --script script-name [--to file.name]

    Выгрузить скрипт с заданным именем (`--to`) или с именем по умолчанию.

## Назначение IP адресов

### Посмотреть список выделенных IP

    $ amz list-ip

### Привязять IP адрес к виртуальной машине

    $ amz bind-ip --ip ip-address --iid instance-id
  
    После остановки виртуальной машины адрес освобождается


## License 

(The MIT License)

Copyright (c) 2011-2012 Temnov Kirill &lt;allselead@gmail.com&gt;

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
