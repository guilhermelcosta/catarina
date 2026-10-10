#pragma once

#include <QHash>
#include <QString>

#include <memory>

// Armazenamento de segredos (id -> valor) num único blob JSON, carregado uma vez
// e mantido em memória. A persistência fica atrás de readRaw/writeRaw, então o
// meio (cofre do SO, arquivo 0600, memória) é trocável sem tocar na lógica.
//
// Sem I/O no cabeçalho: testes injetam a implementação em memória via
// createInMemory() e nunca tocam no cofre real nem no disco.
class SecretStore
{
public:
    virtual ~SecretStore() = default;

    QString value(const QString &id) const;          // "" se não existir
    bool save(const QString &id, const QString &value);
    bool remove(const QString &id);

    // carrega o blob agora (o Backend faz no ctor, antes do QML)
    void preload() const;

    // Cofre do SO quando disponível (e não forçado a arquivo por
    // CATARINA_SECRETS_BACKEND=file); senão arquivo 0600 em filePath.
    // Na primeira vez que o cofre existe vazio, migra o arquivo pra lá e apaga.
    static std::unique_ptr<SecretStore> create(const QString &filePath);
    // implementação em memória, para testes
    static std::unique_ptr<SecretStore> createInMemory();

protected:
    // JSON bruto tipo {"id":"valor"}; "" quando vazio/não existe
    virtual QString readRaw() const = 0;
    virtual bool writeRaw(const QString &json) const = 0;

private:
    void ensureLoaded() const;
    bool persist() const;

    mutable bool m_loaded = false;
    mutable QHash<QString, QString> m_cache;
};
